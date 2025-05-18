#[macro_export]
macro_rules! json_map {
    ( $( $key:ident : $val:expr ),* $(,)? ) => {{
        let mut map = ::serde_json::Map::new();
        $(
            map.insert(stringify!($key).to_string(), ::serde_json::json!($val));
        )*
        map
    }};
}
