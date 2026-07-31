#############################################################################
# Logging configuration
#############################################################################

"""
    setup_logging(logfile::AbstractString; console::Bool=true)

Configure global logging so that all log messages are written to `logfile`
with a timestamp prefix. When `console=true`, messages are also echoed to
the current console logger.

The parent directory of `logfile` is created if it does not exist.
Returns the logger that was installed.

# Example
```julia
setup_logging("log/pras_simulation.log")
@info "Starting the application.."
```
"""
function setup_logging(logfile::AbstractString; console::Bool=true)
    mkpath(dirname(abspath(logfile)))
    file_logger = FileLogger(logfile)

    # Prefix each record written to the file with a timestamp.
    timestamped = TransformerLogger(file_logger) do log
        merge(log, (; message = "$(Dates.format(now(), DATE_FORMAT)) $(log.message)"))
    end

    logger = console ? TeeLogger(global_logger(), timestamped) : timestamped
    global_logger(logger)
    return logger
end
