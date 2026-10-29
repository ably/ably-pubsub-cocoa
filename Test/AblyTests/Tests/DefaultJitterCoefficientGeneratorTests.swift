import XCTest
import AblyPubSubDevice.Private

class DefaultJitterCoefficientGeneratorTests: XCTestCase {
    func test_generatesValuesInExpectedRange() {
        let generator = DefaultJitterCoefficientGenerator()
        let generatedCoefficients = (1...100).map { _ in generator.generateJitterCoefficient() }

        XCTAssertTrue(generatedCoefficients.allSatisfy { (0.8...1.0).contains($0) })
    }

    func test_generatesAVarietyOfValues() {
        let generator = DefaultJitterCoefficientGenerator()
        let generatedCoefficients = (1...100).map { _ in generator.generateJitterCoefficient() }

        XCTAssertGreaterThan(Set(generatedCoefficients).count, 95)
    }
}
