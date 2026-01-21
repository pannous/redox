use std::time::{Duration, Instant};

/// A timeout helper for polling operations.
pub struct Timeout {
    instant: Instant,
    duration: Duration,
}

impl Timeout {
    /// Creates a new timeout with the given duration.
    #[inline]
    pub fn new(duration: Duration) -> Self {
        Self {
            instant: Instant::now(),
            duration,
        }
    }

    /// Creates a new timeout from microseconds.
    #[inline]
    pub fn from_micros(micros: u64) -> Self {
        Self::new(Duration::from_micros(micros))
    }

    /// Creates a new timeout from milliseconds.
    #[inline]
    pub fn from_millis(millis: u64) -> Self {
        Self::new(Duration::from_millis(millis))
    }

    /// Creates a new timeout from seconds.
    #[inline]
    pub fn from_secs(secs: u64) -> Self {
        Self::new(Duration::from_secs(secs))
    }

    /// Checks if the timeout has expired. Returns Ok(()) if not expired, Err(()) if expired.
    #[inline]
    pub fn run(&self) -> Result<(), ()> {
        if self.instant.elapsed() < self.duration {
            // Sleeps in Redox are only evaluated on PIT ticks (a few ms), which is not
            // short enough for a reasonably responsive timeout. However, the clock is
            // highly accurate. So, we yield instead of sleep to reduce latency.
            //TODO: allow timeout that spins instead of yields?
            std::thread::yield_now();
            Ok(())
        } else {
            Err(())
        }
    }
}
