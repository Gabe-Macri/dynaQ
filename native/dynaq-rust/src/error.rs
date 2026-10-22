use std::fmt;

#[derive(Debug, Clone, PartialEq)]
pub enum DspError {
    NullPointer,
    InvalidParameter(String),
    BufferTooSmall { required: usize, provided: usize },
    UnstableFilter { pole_mag: f64 },
    OptimizationFailed(String),
    Io(String),
}

impl fmt::Display for DspError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            DspError::NullPointer => write!(f, "Null pointer argument encountered"),
            DspError::InvalidParameter(msg) => write!(f, "Invalid parameter: {}", msg),
            DspError::BufferTooSmall { required, provided } => {
                write!(f, "Buffer too small: required {}, provided {}", required, provided)
            }
            DspError::UnstableFilter { pole_mag } => {
                write!(f, "Filter pole magnitude |z| = {:.4} >= 1.0 (unstable)", pole_mag)
            }
            DspError::OptimizationFailed(msg) => write!(f, "Optimization failed: {}", msg),
            DspError::Io(msg) => write!(f, "I/O error: {}", msg),
        }
    }
}

impl std::error::Error for DspError {}

#[repr(i32)]
#[derive(Debug, Copy, Clone, PartialEq, Eq)]
pub enum StatusCode {
    Success = 0,
    ErrNullPtr = -1,
    ErrInvalidParam = -2,
    ErrBufferTooSmall = -3,
    ErrUnstableFilter = -4,
    ErrOptimizationFailed = -5,
}

impl From<&DspError> for StatusCode {
    fn from(err: &DspError) -> Self {
        match err {
            DspError::NullPointer => StatusCode::ErrNullPtr,
            DspError::InvalidParameter(_) => StatusCode::ErrInvalidParam,
            DspError::BufferTooSmall { .. } => StatusCode::ErrBufferTooSmall,
            DspError::UnstableFilter { .. } => StatusCode::ErrUnstableFilter,
            DspError::OptimizationFailed(_) => StatusCode::ErrOptimizationFailed,
            DspError::Io(_) => StatusCode::ErrInvalidParam,
        }
    }
}

