import AppKit
import CueCore

/// One ephemeral request. Text never enters preferences, usage learning, or an on-disk history.
@MainActor
final class GPTModel {
    enum Status: Equatable { case idle, loading, completed, stopped, failed }
    typealias StreamOperation = @MainActor (
        String, GPTMode, GPTConfiguration, @escaping @MainActor (String) -> Void
    ) async throws -> Void

    private(set) var input = ""
    private(set) var output = ""
    private(set) var mode: GPTMode = .answer
    private(set) var modelName = ""
    private(set) var status: Status = .idle
    private(set) var isCopying = false
    private(set) var didCopy = false
    var errorMessage: String? { copyErrorMessage ?? requestErrorMessage }
    private(set) var isPresented = false
    // The native view appends each delta once instead of replacing and laying out the entire answer.
    private(set) var outputGeneration = 0
    private(set) var outputRevision = 0
    private(set) var latestDelta = ""
    var isLoading: Bool { status == .loading }
    var canCopy: Bool { isPresented && !output.isEmpty && !isLoading && !isCopying }
    var onChange: (() -> Void)?

    private let configuration: @MainActor () -> GPTConfiguration
    private let stream: StreamOperation
    private let cancelStream: @MainActor () -> Void
    private let copier: @Sendable (String) async throws -> Void
    private var requestTask: Task<Void, Never>?
    private var copyTask: Task<Void, Never>?
    private var requestGeneration = 0
    private var copyGeneration = 0
    private var requestErrorMessage: String?
    private var copyErrorMessage: String?

    convenience init(client: GPTClient, preferences: GPTPreferences,
                     pasteboardName: NSPasteboard.Name = .general) {
        self.init(configuration: { preferences.configuration }, stream: { input, mode, config, delta in
            try await client.stream(input: input, mode: mode, configuration: config, onDelta: delta)
        }, cancelStream: { client.cancel() }, pasteboardName: pasteboardName)
    }

    init(configuration: @escaping @MainActor () -> GPTConfiguration,
         stream: @escaping StreamOperation,
         cancelStream: @escaping @MainActor () -> Void = {},
         pasteboardName: NSPasteboard.Name = .general,
         copier: (@Sendable (String) async throws -> Void)? = nil) {
        self.configuration = configuration
        self.stream = stream
        self.cancelStream = cancelStream
        if let copier { self.copier = copier }
        else {
            let writer = CalculatorCopyService(pasteboardName: pasteboardName)
            self.copier = { try await writer.copy($0) }
        }
    }

    deinit {
        requestTask?.cancel()
        copyTask?.cancel()
    }

    func open(input: String, mode: GPTMode) {
        cancelRequest()
        cancelCopy()
        isPresented = true
        self.input = input
        self.mode = mode
        beginRequest()
    }

    func close() {
        isPresented = false
        cancelRequest()
        cancelCopy()
        input = ""
        clearOutput()
        modelName = ""
        requestErrorMessage = nil
        copyErrorMessage = nil
        status = .idle
        onChange?()
    }

    func stop() {
        guard isPresented, isLoading else { return }
        cancelRequest()
        status = .stopped
        onChange?()
    }

    func cancelPendingCopy() {
        guard isCopying else { return }
        cancelCopy()
        onChange?()
    }

    /// Retrying is always an explicit action because another API request may incur a charge.
    func retry() {
        guard isPresented, !isLoading else { return }
        cancelCopy()
        beginRequest()
    }

    func copyResult() {
        guard canCopy else { return }
        let copiedOutput = output
        let generation = requestGeneration
        copyGeneration += 1
        let copyID = copyGeneration
        isCopying = true
        didCopy = false
        copyErrorMessage = nil
        onChange?()
        copyTask = Task { [weak self, copier] in
            do {
                try Task.checkCancellation()
                try await copier(copiedOutput)
                try Task.checkCancellation()
                guard let self, self.isPresented, self.requestGeneration == generation,
                      self.copyGeneration == copyID else { return }
                self.copyTask = nil
                self.isCopying = false
                self.didCopy = true
                self.onChange?()
            } catch {
                guard !Task.isCancelled, let self, self.isPresented,
                      self.requestGeneration == generation, self.copyGeneration == copyID else { return }
                self.copyTask = nil
                self.isCopying = false
                self.copyErrorMessage = (error as? CalculatorCopyService.Failure) == .denied
                    ? GPTText.shared.clipboardDenied : GPTText.shared.copyError
                self.onChange?()
            }
        }
    }

    private func beginRequest() {
        let config = configuration()
        modelName = config.model
        clearOutput()
        requestErrorMessage = nil
        copyErrorMessage = nil
        didCopy = false
        status = .loading
        requestGeneration += 1
        let generation = requestGeneration
        let requestedInput = input
        let requestedMode = mode
        onChange?()
        requestTask = Task { [weak self, stream] in
            do {
                try Task.checkCancellation()
                try await stream(requestedInput, requestedMode, config) { [weak self] delta in
                    guard let self, self.isPresented, self.requestGeneration == generation,
                          self.isLoading, !Task.isCancelled, !delta.isEmpty else { return }
                    self.output.append(delta)
                    self.latestDelta = delta
                    self.outputRevision += 1
                    self.onChange?()
                }
                try Task.checkCancellation()
                guard let self, self.isPresented, self.requestGeneration == generation else { return }
                self.requestTask = nil
                if self.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.status = .failed
                    self.requestErrorMessage = GPTText.shared.invalidResponse
                } else { self.status = .completed }
                self.onChange?()
            } catch {
                guard let self, self.isPresented, self.requestGeneration == generation else { return }
                self.requestTask = nil
                if error is CancellationError || Task.isCancelled {
                    self.status = .stopped
                } else {
                    self.status = .failed
                    self.requestErrorMessage = GPTText.shared.message(for: error)
                }
                self.onChange?()
            }
        }
    }

    private func cancelRequest() {
        // Invalidate callbacks before cancellation; even a transport ignoring cancellation cannot publish.
        requestGeneration += 1
        requestTask?.cancel()
        requestTask = nil
        cancelStream()
    }

    private func cancelCopy() {
        copyGeneration += 1
        copyTask?.cancel()
        copyTask = nil
        isCopying = false
        didCopy = false
    }

    private func clearOutput() {
        output = ""
        latestDelta = ""
        outputGeneration += 1
        outputRevision = 0
    }
}
