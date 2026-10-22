"""dynaQ Python Backend & SDK Exceptions.

Defines strongly typed, actionable error categories for real-time audio routing,
IPC communication, and mathematical DSP optimizations.
"""


class DynaQError(Exception):
    """Base exception for all dynaQ audio system errors."""

    def __init__(self, message: str, code: int = -1):
        super().__init__(message)
        self.message = message
        self.code = code

    def __str__(self) -> str:
        return f"[DYNAQ_ERR_{self.code}] {self.message}"


class DynaQConnectionError(DynaQError):
    """Raised when unable to connect to the dynaQ IPC socket or backend daemon."""

    def __init__(self, message: str = "Unable to connect to dynaQ IPC socket (/tmp/dynaq_ipc.sock)"):
        super().__init__(message, code=101)


class DynaQProtocolError(DynaQError):
    """Raised when an IPC response payload is malformed or invalid."""

    def __init__(self, message: str):
        super().__init__(message, code=102)


class DynaQDSPError(DynaQError):
    """Raised when DSP parameters (filter poles, frequency, sample rate) violate stability."""

    def __init__(self, message: str):
        super().__init__(message, code=201)


class DynaQOptimizationError(DynaQError):
    """Raised when AutoEQ curve fitting or optimization fails to converge."""

    def __init__(self, message: str):
        super().__init__(message, code=301)

