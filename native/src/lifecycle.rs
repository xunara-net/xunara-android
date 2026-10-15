use anyhow::{Context, Result, ensure};
use tokio::sync::watch;

struct Running {
    generation: u64,
    started: bool,
    stop: watch::Sender<bool>,
}

pub struct Lifecycle {
    next: u64,
    running: Option<Running>,
}

impl Lifecycle {
    pub const fn new() -> Self {
        Self {
            next: 0,
            running: None,
        }
    }

    pub fn prepare(&mut self) -> Result<u64> {
        ensure!(self.running.is_none(), "上一连接尚未停止");
        self.next = self
            .next
            .checked_add(1)
            .filter(|generation| *generation <= i64::MAX as u64)
            .context("连接序号已耗尽")?;
        let (stop, _receiver) = watch::channel(false);
        self.running = Some(Running {
            generation: self.next,
            started: false,
            stop,
        });
        Ok(self.next)
    }

    pub fn start(&mut self, generation: u64) -> Result<watch::Receiver<bool>> {
        let running = self
            .running
            .as_mut()
            .filter(|running| running.generation == generation)
            .context("连接已失效")?;
        ensure!(!running.started, "连接已经启动");
        running.started = true;
        Ok(running.stop.subscribe())
    }

    pub fn stop(&self, generation: u64) {
        if let Some(running) = self
            .running
            .as_ref()
            .filter(|running| running.generation == generation)
        {
            // 即使工作线程还没订阅，也必须保留用户先前点击的断开意图。
            running.stop.send_replace(true);
        }
    }

    pub fn finish(&mut self, generation: u64) {
        if self
            .running
            .as_ref()
            .is_some_and(|running| running.generation == generation)
        {
            self.running = None;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cancellation_before_worker_start_is_not_lost() {
        let mut lifecycle = Lifecycle::new();
        let generation = lifecycle.prepare().unwrap();
        lifecycle.stop(generation);
        lifecycle.stop(generation);
        assert!(*lifecycle.start(generation).unwrap().borrow());
        assert!(lifecycle.start(generation).is_err());
    }

    #[test]
    fn stale_service_callbacks_cannot_stop_a_new_connection() {
        let mut lifecycle = Lifecycle::new();
        let previous = lifecycle.prepare().unwrap();
        assert!(lifecycle.prepare().is_err());
        lifecycle.finish(previous);
        let current = lifecycle.prepare().unwrap();
        let receiver = lifecycle.start(current).unwrap();
        lifecycle.stop(previous);
        lifecycle.finish(previous);
        assert!(!*receiver.borrow());
        assert!(lifecycle.prepare().is_err());
        lifecycle.stop(current);
        assert!(*receiver.borrow());
        lifecycle.finish(current);
        assert!(lifecycle.prepare().is_ok());
    }
}
