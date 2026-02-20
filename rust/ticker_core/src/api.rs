#[derive(uniffi::Record, Debug, Clone)]
pub struct PriceUpdate {
    pub symbol: String,
    pub price: f64,
    pub timestamp_ms: i64,
}

#[uniffi::export]
pub trait PriceListener: Send + Sync {
    fn on_price(&self, update: PriceUpdate);
}
