use std::sync::{Condvar, Mutex};
pub struct Semaphore {
  count: Mutex<usize>,
  condvar: Condvar,
}

impl Semaphore {
  pub fn new(limit: usize) -> Self {
    Self {
      count: Mutex::new(limit),
      condvar: Condvar::new(),
    }
  }

  pub fn acquire(&self) {
    // let thread_id = std::thread::current().id();
    let mut count = self.count.lock().unwrap();
    while *count == 0 {
      // println!("[{thread_id:?}] 🚫 Semaphore full. Waiting...");
      count = self.condvar.wait(count).unwrap();
    }
    *count -= 1;
    // println!(
    // "[{thread_id:?}] ✅ Acquired semaphore. Remaining: {}",
    //     *count
    // );
  }

  pub fn release(&self) {
    // let thread_id = std::thread::current().id();
    let mut count = self.count.lock().unwrap();
    *count += 1;
    // println!(
    //     "[{thread_id:?}] 🔓 Released semaphore. Remaining: {}",
    //     *count
    // );
    self.condvar.notify_one();
  }
}
