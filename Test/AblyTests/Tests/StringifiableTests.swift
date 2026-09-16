import AblyPubSubDevice
import Nimble
import XCTest

class StringifiableTests: XCTestCase {
    func test__001__Stringifiable__type_conversion__as_string() {
        expect(
            Stringifiable(string: "Lorem Ipsum").stringValue
        )
        .to(
            equal("Lorem Ipsum")
        )
    }

    func test__002__Stringifiable__type_conversion__as_bool__true_() {
        expect {
            Stringifiable(bool: true).stringValue
        }
        .to(
            equal("true")
        )
    }

    func test__003__Stringifiable__type_conversion__as_bool__false_() {
        expect {
            Stringifiable(bool: false).stringValue
        }
        .to(
            equal("false")
        )
    }

    func test__004__Stringifiable__type_conversion__as_integer_that_is_not_treated_as_bool__false_() {
        expect {
            Stringifiable(number: NSNumber(value: 0)).stringValue
        }
        .to(
            equal("0")
        )
    }

    func test__005__Stringifiable__type_conversion__as_integer_that_is_not_treated_as_bool__true_() {
        expect {
            Stringifiable(number: NSNumber(value: 1)).stringValue
        }
        .to(
            equal("1")
        )
    }

    func test__006__Stringifiable__type_conversion__as_number__Int_() {
        expect {
            Stringifiable(number: NSNumber(value: 12)).stringValue
        }
        .to(
            equal("12")
        )
    }

    func test__007__Stringifiable__type_conversion__as_number__Float_1_decimal_digit_() {
        expect {
            Stringifiable(number: NSNumber(value: 0.1)).stringValue
        }
        .to(
            equal("0.1")
        )
    }

    func test__008__Stringifiable__type_conversion__as_number__Float_2_decimal_digits_() {
        expect {
            Stringifiable(number: NSNumber(value: 0.12)).stringValue
        }
        .to(
            equal("0.12")
        )
    }

    func test__009__Stringifiable__type_conversion__as_number__Float_4_decimal_digits_() {
        expect {
            Stringifiable(number: NSNumber(value: 0.1234)).stringValue
        }
        .to(
            equal("0.1234")
        )
    }
}
