//
//  NetworkPathObserver.swift
//  MioCam
//

import Network

final class NetworkPathObserver {
    private let onChange: () -> Void
    private var monitor: NWPathMonitor?
    private var previousInterfaces: Set<NWInterface.InterfaceType>?

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    func start() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self, weak monitor] path in
            guard let self, let monitor, self.monitor === monitor, path.status == .satisfied else { return }
            let interfaces = Set(path.availableInterfaces.map(\.type).filter { path.usesInterfaceType($0) })
            let previous = self.previousInterfaces
            self.previousInterfaces = interfaces
            if let previous, previous != interfaces {
                self.onChange()
            }
        }
        monitor.start(queue: .main)
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
        previousInterfaces = nil
    }
}
