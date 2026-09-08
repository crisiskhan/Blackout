import BlackoutCore
import CoreNFC
import DesignSystem
import SwiftUI

/// Local NDEF read/write of the 4–8 party code. iPhone cannot emulate a tag (no public HCE).
@MainActor
final class PartyNFCCoordinator: NSObject, NFCNDEFReaderSessionDelegate {
    enum Mode {
        case share(String)
        case join((String) -> Void)
    }

    var onFail: ((String) -> Void)?
    private var session: NFCNDEFReaderSession?
    private var mode: Mode?

    static var hardwareAvailable: Bool {
        NFCNDEFReaderSession.readingAvailable
    }

    func share(code: String) {
        start(mode: .share(PartyNFC.payload(code: code)))
    }

    func join(onCode: @escaping (String) -> Void) {
        start(mode: .join(onCode))
    }

    private func start(mode: Mode) {
        guard Self.hardwareAvailable else {
            onFail?(PartyNFC.sessionFailed)
            return
        }
        self.mode = mode
        let next = NFCNDEFReaderSession(delegate: self, queue: .main, invalidateAfterFirstRead: false)
        switch mode {
        case .share:
            next.alertMessage = "Hold this phone to an NFC tag to write the party code."
        case .join:
            next.alertMessage = "Hold this phone to an NFC tag to read the party code."
        }
        session = next
        next.begin()
    }

    func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {}

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        self.session = nil
        if let nfc = error as? NFCReaderError {
            switch nfc.code {
            case .readerSessionInvalidationErrorUserCanceled:
                return
            case .readerSessionInvalidationErrorFirstNDEFTagRead:
                return
            case .readerSessionInvalidationErrorSystemIsBusy,
                 .readerSessionInvalidationErrorSessionTerminatedUnexpectedly,
                 .readerSessionInvalidationErrorSessionTimeout:
                onFail?(PartyNFC.sessionFailed)
            default:
                onFail?(PartyNFC.denied)
            }
        } else {
            onFail?(PartyNFC.sessionFailed)
        }
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        handle(messages: messages, session: session)
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [any NFCNDEFTag]) {
        guard let tag = tags.first else { return }
        session.connect(to: tag) { [weak self] error in
            if error != nil {
                session.invalidate(errorMessage: PartyNFC.sessionFailed)
                return
            }
            tag.queryNDEFStatus { status, _, error in
                if error != nil {
                    session.invalidate(errorMessage: PartyNFC.sessionFailed)
                    return
                }
                switch self?.mode {
                case .share(let code):
                    self?.write(code, to: tag, status: status, session: session)
                case .join:
                    self?.read(from: tag, session: session)
                case .none:
                    session.invalidate()
                }
            }
        }
    }

    private func write(
        _ code: String,
        to tag: any NFCNDEFTag,
        status: NFCNDEFStatus,
        session: NFCNDEFReaderSession
    ) {
        guard status == .readWrite,
              let record = NFCNDEFPayload.wellKnownTypeTextPayload(string: code, locale: Locale(identifier: "en"))
        else {
            session.invalidate(errorMessage: PartyNFC.sessionFailed)
            return
        }
        tag.writeNDEF(NFCNDEFMessage(records: [record])) { error in
            if error != nil {
                session.invalidate(errorMessage: PartyNFC.sessionFailed)
                return
            }
            session.alertMessage = "Shared \(code)."
            session.invalidate()
        }
    }

    private func read(from tag: any NFCNDEFTag, session: NFCNDEFReaderSession) {
        tag.readNDEF { [weak self] message, error in
            if error != nil || message == nil {
                session.invalidate(errorMessage: PartyNFC.sessionFailed)
                return
            }
            self?.handle(messages: [message!], session: session)
        }
    }

    private func handle(messages: [NFCNDEFMessage], session: NFCNDEFReaderSession) {
        let payloads = messages.flatMap { $0.records }.compactMap(Self.string(from:))
        guard let code = PartyNFC.parseMessagePayloads(payloads) else {
            session.invalidate(errorMessage: PartyNFC.sessionFailed)
            return
        }
        if case .join(let onCode) = mode {
            session.alertMessage = code
            session.invalidate()
            onCode(code)
            return
        }
        session.invalidate()
    }

    private static func string(from record: NFCNDEFPayload) -> String? {
        let (text, _) = record.wellKnownTypeTextPayload()
        if let text { return text }
        if let url = record.wellKnownTypeURIPayload() {
            return url.absoluteString
        }
        return String(data: record.payload, encoding: .utf8)
    }
}
