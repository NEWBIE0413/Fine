import CoreTransferable
import UniformTypeIdentifiers

/// Private drag data keeps ordinary text/file drops out of session ordering.
struct OpenSessionDrag: Codable, Transferable {
    let windowID: UUID
    let sessionID: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: UTType(exportedAs: "com.fine.open-session", conformingTo: .data))
    }
}

enum SessionInsertionEdge { case before, after }
