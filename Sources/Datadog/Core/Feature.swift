/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Lists different types of data directories used by the feature.
internal struct FeatureDirectories {
    /// Data directory for storing unauthorized data collected without knowing the tracking consent value.
    /// Due to the consent change, data in this directory may be either moved to `authorized` folder or entirely deleted.
    let unauthorized: Directory
    /// Data directory for storing authorized data collected when tracking consent is granted.
    /// Consent change does not impact data already stored in this folder.
    /// Data in this folder gets uploaded to the server.
    let authorized: Directory
}

/// Container with dependencies common to all features (Logging, Tracing and RUM).
internal struct FeaturesCommonDependencies {
    let consentProvider: ConsentProvider
    let performance: PerformancePreset
    let httpClient: HTTPClient
    let mobileDevice: MobileDevice
    let dateProvider: DateProvider
    let dateCorrector: DateCorrectorType
    let userInfoProvider: UserInfoProvider
    let networkConnectionInfoProvider: NetworkConnectionInfoProviderType
    let carrierInfoProvider: CarrierInfoProviderType
    let launchTimeProvider: LaunchTimeProviderType
}

internal struct FeatureStorage {
    /// Writes data to files.
    let writer: Writer
    /// Reads data from files.
    let reader: Reader

    init(
        featureName: String,
        dataFormat: DataFormat,
        directories: FeatureDirectories,
        commonDependencies: FeaturesCommonDependencies
    ) {
        let readWriteQueue = DispatchQueue(
            label: "com.datadoghq.ios-sdk-\(featureName)-read-write",
            target: .global(qos: .utility)
        )
        let authorizedFilesOrchestrator = FilesOrchestrator(
            directory: directories.authorized,
            performance: commonDependencies.performance,
            dateProvider: commonDependencies.dateProvider
        )
        let unauthorizedFilesOrchestrator = FilesOrchestrator(
            directory: directories.unauthorized,
            performance: commonDependencies.performance,
            dateProvider: commonDependencies.dateProvider
        )

        let consentAwareDataWriter = ConsentAwareDataWriter(
            consentProvider: commonDependencies.consentProvider,
            readWriteQueue: readWriteQueue,
            dataProcessorFactory: DataProcessorFactory(
                unauthorizedFileWriter: FileWriter(
                    dataFormat: dataFormat,
                    orchestrator: unauthorizedFilesOrchestrator
                ),
                authorizedFileWriter: FileWriter(
                    dataFormat: dataFormat,
                    orchestrator: authorizedFilesOrchestrator
                )
            ),
            dataMigratorFactory: DataMigratorFactory(
                directories: directories
            )
        )

        let dataReader = DataReader(
            readWriteQueue: readWriteQueue,
            fileReader: FileReader(dataFormat: dataFormat, orchestrator: authorizedFilesOrchestrator)
        )

        self.init(
            writer: consentAwareDataWriter,
            reader: dataReader
        )
    }

    init(writer: Writer, reader: Reader) {
        self.writer = writer
        self.reader = reader
    }
}

internal struct FeatureUpload {
    /// Uploads data to server.
    let uploader: DataUploadWorkerType

    init(
        featureName: String,
        storage: FeatureStorage,
        uploadHTTPHeaders: HTTPHeaders,
        uploadURLProvider: UploadURLProvider,
        commonDependencies: FeaturesCommonDependencies
    ) {
        let uploadQueue = DispatchQueue(
            label: "com.datadoghq.ios-sdk-\(featureName)-upload",
            target: .global(qos: .utility)
        )

        let uploadConditions = DataUploadConditions(
            batteryStatus: BatteryStatusProvider(mobileDevice: commonDependencies.mobileDevice),
            networkConnectionInfo: commonDependencies.networkConnectionInfoProvider
        )

        let dataUploader = DataUploader(
            urlProvider: uploadURLProvider,
            httpClient: commonDependencies.httpClient,
            httpHeaders: uploadHTTPHeaders
        )

        self.init(
            uploader: DataUploadWorker(
                queue: uploadQueue,
                fileReader: storage.reader,
                dataUploader: dataUploader,
                uploadConditions: uploadConditions,
                delay: DataUploadDelay(performance: commonDependencies.performance),
                featureName: featureName
            )
        )
    }

    init(uploader: DataUploadWorkerType) {
        self.uploader = uploader
    }
}
