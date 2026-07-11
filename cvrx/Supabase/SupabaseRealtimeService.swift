import Foundation

struct SupabaseRealtimeConnectionInfo: Sendable {
    let config: SupabaseConfig
    let accessToken: String
    let facilityID: UUID

    var websocketURL: URL? {
        var components = URLComponents(url: config.projectURL, resolvingAgainstBaseURL: false)
        components?.scheme = "wss"
        components?.path = "/realtime/v1/websocket"
        components?.queryItems = [
            URLQueryItem(name: "apikey", value: config.anonKey),
            URLQueryItem(name: "vsn", value: "2.0.0")
        ]
        return components?.url
    }
}

actor SupabaseRealtimeService {
    enum RealtimeError: LocalizedError {
        case missingWebsocketURL
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .missingWebsocketURL:
                return "Unable to create Supabase Realtime websocket URL."
            case .encodingFailed:
                return "Unable to encode Supabase Realtime message."
            }
        }
    }

    private let connectionInfo: SupabaseRealtimeConnectionInfo
    private let onDatabaseChange: @Sendable () async -> Void
    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var isRunning = false
    private var refCounter = 0

    private let topic = "realtime:cvrx-orders"
    private let subscribedTables = [
        "orders",
        "rxcui_concepts",
        "ndc_products",
        "rxcui_concept_ndc_products",
        "ordered_components",
        "utilized_lots",
        "scan_overrides",
        "compound_captures",
        "capture_flags",
        "verification_records",
        "remediation_requests",
        "remediation_captures",
        "remediation_lot_changes",
        "audit_events"
    ]

    init(
        connectionInfo: SupabaseRealtimeConnectionInfo,
        onDatabaseChange: @escaping @Sendable () async -> Void
    ) {
        self.connectionInfo = connectionInfo
        self.onDatabaseChange = onDatabaseChange
    }

    func start() async {
        guard !isRunning else { return }
        isRunning = true
        await connect()
    }

    func stop() async {
        isRunning = false
        reconnectTask?.cancel()
        receiveTask?.cancel()
        heartbeatTask?.cancel()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        reconnectTask = nil
        receiveTask = nil
        heartbeatTask = nil
        webSocketTask = nil
    }

    private func connect() async {
        guard isRunning else { return }
        guard let url = connectionInfo.websocketURL else {
            print(RealtimeError.missingWebsocketURL.localizedDescription)
            return
        }

        webSocketTask?.cancel(with: .goingAway, reason: nil)

        let task = URLSession.shared.webSocketTask(with: url)
        webSocketTask = task
        task.resume()

        do {
            try await sendJoin()
            startHeartbeat()
            startReceiveLoop()
        } catch {
            print("Supabase realtime join failed: \(error.localizedDescription)")
            scheduleReconnect()
        }
    }

    private func startReceiveLoop() {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            guard let self else { return }
            await self.receiveLoop()
        }
    }

    private func receiveLoop() async {
        while isRunning, let webSocketTask {
            do {
                let message = try await webSocketTask.receive()
                await handle(message)
            } catch {
                if isRunning {
                    print("Supabase realtime receive failed: \(error.localizedDescription)")
                    scheduleReconnect()
                }
                return
            }
        }
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(25))
                guard !Task.isCancelled else { return }
                await self.sendHeartbeat()
            }
        }
    }

    private func scheduleReconnect() {
        guard isRunning, reconnectTask == nil else { return }
        receiveTask?.cancel()
        heartbeatTask?.cancel()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil

        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self else { return }
            await self.clearReconnectTask()
            await self.connect()
        }
    }

    private func clearReconnectTask() {
        reconnectTask = nil
    }

    private func sendJoin() async throws {
        let changes = subscribedTables.map { table in
            JSONValue.object([
                "event": .string("*"),
                "schema": .string("public"),
                "table": .string(table),
                "filter": .string("facility_id=eq.\(connectionInfo.facilityID.uuidString)")
            ])
        }

        let payload = JSONValue.object([
            "config": .object([
                "broadcast": .object([
                    "ack": .bool(false),
                    "self": .bool(false)
                ]),
                "presence": .object([
                    "enabled": .bool(false)
                ]),
                "postgres_changes": .array(changes)
            ]),
            "access_token": .string(connectionInfo.accessToken)
        ])

        try await send(event: "phx_join", topic: topic, payload: payload)
    }

    private func sendHeartbeat() async {
        do {
            try await send(event: "heartbeat", topic: "phoenix", payload: .object([:]), joinRef: .null)
        } catch {
            if isRunning {
                print("Supabase realtime heartbeat failed: \(error.localizedDescription)")
                scheduleReconnect()
            }
        }
    }

    private func send(
        event: String,
        topic: String,
        payload: JSONValue,
        joinRef: JSONValue? = nil
    ) async throws {
        guard let webSocketTask else { return }
        let ref = nextRef()
        let message: [JSONValue] = [
            joinRef ?? .string(ref),
            .string(ref),
            .string(topic),
            .string(event),
            payload
        ]

        let data = try JSONEncoder.supabase.encode(message)
        guard let text = String(data: data, encoding: .utf8) else {
            throw RealtimeError.encodingFailed
        }
        try await webSocketTask.send(.string(text))
    }

    private func nextRef() -> String {
        refCounter += 1
        return String(refCounter)
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) async {
        let text: String?
        switch message {
        case .string(let value):
            text = value
        case .data(let data):
            text = String(data: data, encoding: .utf8)
        @unknown default:
            text = nil
        }

        guard
            let text,
            let data = text.data(using: .utf8),
            let frame = try? JSONDecoder.supabase.decode([JSONValue].self, from: data),
            frame.count >= 5,
            case .string(let event) = frame[3]
        else { return }

        switch event {
        case "postgres_changes":
            await onDatabaseChange()
        case "phx_close", "phx_error":
            scheduleReconnect()
        case "system":
            if case .object(let payload) = frame[4],
               case .string(let status)? = payload["status"],
               status == "error" {
                print("Supabase realtime system error: \(payload)")
            }
        case "phx_reply":
            if case .object(let payload) = frame[4],
               case .string(let status)? = payload["status"],
               status == "error" {
                print("Supabase realtime join/reply error: \(payload)")
            }
        default:
            break
        }
    }
}
