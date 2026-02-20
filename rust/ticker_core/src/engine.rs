use crate::api::{PriceListener, PriceUpdate};
use rand::Rng;
use std::collections::{HashMap, VecDeque};
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc, Mutex,
};
use tokio::runtime::Runtime;
use tokio::time::{sleep, Duration};

struct EngineState {
    cancel: AtomicBool,
    running: AtomicBool,
    queue: Mutex<VecDeque<PriceUpdate>>,
}

#[derive(uniffi::Object)]
pub struct TickerEngine {
    state: Arc<EngineState>,
}

#[uniffi::export]
impl TickerEngine {
    #[uniffi::constructor]
    pub fn new() -> Arc<Self> {
        Arc::new(Self {
            state: Arc::new(EngineState {
                cancel: AtomicBool::new(false),
                running: AtomicBool::new(false),
                queue: Mutex::new(VecDeque::new()),
            }),
        })
    }

    pub fn start_tracking(&self, symbols: Vec<String>, listener: Arc<dyn PriceListener>) {
        if symbols.is_empty() {
            return;
        }

        if self.state.running.swap(true, Ordering::SeqCst) {
            return;
        }

        self.state.cancel.store(false, Ordering::SeqCst);

        let state = self.state.clone();
        std::thread::spawn(move || {
            let runtime = match Runtime::new() {
                Ok(runtime) => runtime,
                Err(err) => {
                    eprintln!("Failed to start tokio runtime: {err}");
                    state.running.store(false, Ordering::SeqCst);
                    return;
                }
            };

            runtime.block_on(async move {
                let mut rng = rand::thread_rng();
                let mut prices: HashMap<String, f64> = symbols
                    .into_iter()
                    .map(|symbol| {
                        let base = rng.gen_range(90.0..110.0);
                        (symbol, base)
                    })
                    .collect();

                while !state.cancel.load(Ordering::SeqCst) {
                    for (symbol, price) in prices.iter_mut() {
                        let delta = rng.gen_range(-1.0..1.0);
                        *price = (*price + delta).max(0.01);

                        let update = PriceUpdate {
                            symbol: symbol.clone(),
                            price: *price,
                            timestamp_ms: current_timestamp_ms(),
                        };

                        listener.on_price(update.clone());

                        if let Ok(mut queue) = state.queue.lock() {
                            queue.push_back(update);
                        }
                    }

                    sleep(Duration::from_millis(500)).await;
                }

                state.running.store(false, Ordering::SeqCst);
                println!("TickerEngine stopped");
            });
        });
    }

    pub fn cancel(&self) {
        self.state.cancel.store(true, Ordering::SeqCst);
    }

    pub fn drain_updates(&self, max: u32) -> Vec<PriceUpdate> {
        let mut updates = Vec::new();
        let mut queue = match self.state.queue.lock() {
            Ok(queue) => queue,
            Err(poisoned) => poisoned.into_inner(),
        };

        for _ in 0..max {
            if let Some(update) = queue.pop_front() {
                updates.push(update);
            } else {
                break;
            }
        }

        updates
    }
}

fn current_timestamp_ms() -> i64 {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default();
    now.as_millis() as i64
}
