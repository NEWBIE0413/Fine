import Foundation

/// 홈 화면 맨 위의 한 문장.
///
/// 기능을 설명하는 자리가 아니다 — 열 때마다 읽히는 자리이므로, 안내문보다
/// 오래 견디는 문장이 낫다. 니체는 1900년에 죽었고 그 글은 퍼블릭 도메인이다.
struct HomeEpigraph {
    let text: String
    let attribution: String

    static let current = HomeEpigraph(
        text: "One must still have chaos in oneself\nto give birth to a dancing star.",
        attribution: "Nietzsche · Thus Spoke Zarathustra"
    )
}
