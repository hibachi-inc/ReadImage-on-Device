import Foundation

/// 非同期処理の結果を、スレッドをまたいで安全に受け渡すための小さな箱。
///
/// blockingValue が作った Task から書き込み、待機側から読み出した直後に
/// 破棄するため、実際のアクセスは常にセマフォで同期される。
final class AsyncResultBox<T: Sendable>: @unchecked Sendable {
    var value: Swift.Result<T, Error>?
}
