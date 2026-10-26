import AppKit
import Combine

final class LocalWorkState: ObservableObject {
    @Published private(set) var isWorking = false
    @Published private(set) var isCancelling = false
    @Published var message: String?
    @Published private(set) var progress = 0.0
    @Published private(set) var status = ""
    var onBusy: ((Bool) -> Void)?
    var onExport: (([URL]) -> Void)?
    var closeWindow: (() -> Void)?
    private var token = WorkCancellation()
    private var closeRequested = false
    private let queue = DispatchQueue(label: "io.github.qingyou.local-work", qos: .userInitiated)

    func start(_ title: String, body: @escaping (WorkCancellation, @escaping (Int, Int) -> Void) throws -> [URL]) {
        guard !isWorking else { return }
        token = WorkCancellation(); let cancellation = token
        isWorking = true; isCancelling = false; progress = 0; message = nil; status = title
        onBusy?(true)
        queue.async { [self] in
            let result = Result { try body(cancellation) { done, total in
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.isWorking else { return }
                    self.progress = total > 0 ? Double(done) / Double(total) : 0
                    if !self.isCancelling { self.status = "\(title) · \(done) / \(total)" }
                }
            } }
            DispatchQueue.main.async {
                self.isWorking = false; self.isCancelling = false; self.onBusy?(false)
                switch result {
                case .success(let outputs): self.status = "处理完成"; self.onExport?(outputs)
                case .failure(let error) where error is CancellationError: self.status = "已取消，未生成新文件"
                case .failure(let error): self.message = error.localizedDescription; self.status = ""
                }
                if self.closeRequested { self.closeWindow?() }
            }
        }
    }
    func cancel(closeAfterwards: Bool = false) {
        guard isWorking else { if closeAfterwards { closeWindow?() }; return }
        closeRequested = closeAfterwards
        isCancelling = true; status = "正在取消…"; token.cancel()
    }
}

protocol UtilitySession: AnyObject {
    var work: LocalWorkState { get }
    func stopPreview()
}
