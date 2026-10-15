import XCTest
@testable import QuotaCore

private final class ToggleProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class AccountToggleTests: XCTestCase {
    private var directory: URL!
    private var client: ProxyClient!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let key = directory.appendingPathComponent("key")
        try "test-management-key".write(to: key, atomically: true, encoding: .utf8)
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [ToggleProtocol.self]
        client = ProxyClient(configuration: Configuration(managementKeyFile: key.path), session: URLSession(configuration: sessionConfig))
    }
    override func tearDownWithError() throws {
        ToggleProtocol.handler = nil
        try FileManager.default.removeItem(at: directory)
    }
    private func records(_ disabled: Bool, includeTarget: Bool = true, status: String? = nil) -> Data {
        let target: [String: Any] = ["auth_index":"target", "name":"claude-example.json", "provider":"claude", "disabled":disabled,
                                     "status":status ?? (disabled ? "disabled" : "active")]
        let other: [String: Any] = ["auth_index":"other", "name":"claude-other.json", "provider":"claude", "disabled":true]
        return try! JSONSerialization.data(withJSONObject: ["files": includeTarget ? [target,other] : [other]])
    }
    private var account: SubscriptionAccount { .init(id:"target", provider:.claude, label:"Example") }
    func testToggleTargetsOneExactAccountAndReadsBack() async throws {
        var disabled = false
        var methods: [String] = []
        ToggleProtocol.handler = { request in
            methods.append(request.httpMethod!)
            if request.httpMethod == "PATCH" {
                XCTAssertEqual(request.url?.path, "/v0/management/auth-files/status")
                // URLSession may provide the request body as a stream to URLProtocol.
                var data = request.httpBody ?? Data()
                if let stream = request.httpBodyStream {
                    stream.open(); defer { stream.close() }
                    var bytes = [UInt8](repeating:0,count:1024)
                    while stream.hasBytesAvailable { let count = stream.read(&bytes, maxLength:bytes.count); if count <= 0 { break }; data.append(contentsOf:bytes.prefix(count)) }
                }
                let body = try JSONSerialization.jsonObject(with:data) as! [String:Any]
                XCTAssertEqual(body["name"] as? String,"claude-example.json")
                XCTAssertEqual(body["auth_index"] as? String,"target")
                XCTAssertEqual(body["disabled"] as? Bool,true)
                disabled = true
                return (200, Data("{}".utf8))
            }
            return (200,self.records(disabled))
        }
        let result = try await client.setAccountEnabled(account, enabled:false)
        XCTAssertTrue(result.disabled)
        XCTAssertEqual(methods,["GET","PATCH","GET"])
    }
    func testLostWriteResponseIsReconciledWithoutReplay() async throws {
        var disabled = false
        var patches = 0
        ToggleProtocol.handler = { request in
            if request.httpMethod == "PATCH" { disabled = true; patches += 1; throw URLError(.networkConnectionLost) }
            return (200,self.records(disabled))
        }
        let result = try await client.setAccountEnabled(account, enabled:false)
        XCTAssertTrue(result.disabled)
        XCTAssertEqual(patches,1)
    }
    func testUnchangedReadbackDoesNotClaimSuccess() async throws {
        ToggleProtocol.handler = { request in
            request.httpMethod == "PATCH" ? (200,Data("{}".utf8)) : (200,self.records(false))
        }
        do { _ = try await client.setAccountEnabled(account,enabled:false); XCTFail("Unconfirmed mutation accepted") }
        catch ProxyError.accountUpdate { }
    }
    func testMissingTargetNeverPatchesAnotherAccount() async throws {
        var patches = 0
        ToggleProtocol.handler = { request in
            if request.httpMethod == "PATCH" { patches += 1 }
            return (200,self.records(false,includeTarget:false))
        }
        do { _ = try await client.setAccountEnabled(account,enabled:false); XCTFail("Missing target accepted") }
        catch ProxyError.accountUpdate { }
        XCTAssertEqual(patches,0)
    }
    func testAlreadyDisabledIsReadOnly() async throws {
        var requests = 0
        ToggleProtocol.handler = { request in requests += 1; XCTAssertEqual(request.httpMethod,"GET"); return (200,self.records(true)) }
        let result = try await client.setAccountEnabled(account,enabled:false)
        XCTAssertTrue(result.disabled)
        XCTAssertEqual(requests,1)
    }
    func testAccountTheProxyMarksDisabledIsTreatedAsDisabled() async throws {
        var requests = 0
        ToggleProtocol.handler = { request in requests += 1; XCTAssertEqual(request.httpMethod,"GET"); return (200,self.records(false,status:"disabled")) }
        let result = try await client.setAccountEnabled(account,enabled:false)
        XCTAssertTrue(result.disabled)
        XCTAssertEqual(requests,1)
    }
    func testEnablingIsConfirmedOnlyOnceTheProxyNoLongerMarksItDisabled() async throws {
        var enabled = false
        ToggleProtocol.handler = { request in
            if request.httpMethod == "PATCH" { enabled = true; return (200,Data("{}".utf8)) }
            return (200,self.records(false,status:enabled ? "active" : "disabled"))
        }
        let result = try await client.setAccountEnabled(account,enabled:true)
        XCTAssertFalse(result.disabled)
    }
}
