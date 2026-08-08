import XCTest
import OrbitCore
import OrbitSQLite
import OrbitStore
@testable import OrbitWrite

/// FIELD-NOTES FN-19 — a person arrived named "his brother". That string is a
/// pointer, not a name: person matching runs on the name, so it does not
/// duplicate people, it *merges strangers* — the one failure adding evidence
/// cannot undo.
final class PersonNamingTests: XCTestCase {
    var store: WriteStore!
    var edits: UserEditService!

    override func setUpWithError() throws {
        store = try WriteStore.inMemory(clock: FixedClock("2026-07-29T12:00:00Z"))
        edits = UserEditService(store)
    }

    func testPointerShapedNamesAreRefused() throws {
        for name in ["his brother", "her boss", "my roommate", "their girlfriend",
                     "His Brother", "John's friend from work", "Sarah\u{2019}s dad"] {
            XCTAssertNotNil(UserEditService.relationshipPointer(in: name),
                            "\(name) is a pointer — a name-possessive points as hard as a pronoun")
            XCTAssertThrowsError(try edits.createPerson(displayName: name),
                                 "\(name) must not become a person row")
        }
    }

    /// The guard must not eat real names. A relationship word is only a pointer
    /// when something possesses it.
    func testOrdinaryNamesAreUntouched() throws {
        for name in ["Sarah", "Mother Teresa", "Nikos", "Sarah Chen", "Friend",
                     "Brother Ali", "Dad"] {
            XCTAssertNil(UserEditService.relationshipPointer(in: name),
                         "\(name) is a name, not a pointer")
            XCTAssertNoThrow(try edits.createPerson(displayName: name))
        }
    }

    func testEmptyNamesAreRefused() {
        XCTAssertThrowsError(try edits.createPerson(displayName: "   "))
    }

    func testNamesAreTrimmed() throws {
        let id = try edits.createPerson(displayName: "  Sana  ")
        XCTAssertEqual(
            try store.db.scalar("SELECT display_name FROM person WHERE id=?",
                                [.text(id)]).stringValue, "Sana")
    }
}
