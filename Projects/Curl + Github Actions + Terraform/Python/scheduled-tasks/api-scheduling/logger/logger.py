"""Script to configure logs"""
import json
import logging
import sys
import time
import traceback
from functools import wraps

class DatadogJsonFormatter(logging.Formatter):
    def format(self, record):
        record.message = record.getMessage()
        if self.usesTime():
            record.asctime = self.formatTime(record, self.datefmt)
        j = {
            "level": record.levelname,
            "timestamp": "%(asctime)s.%(msecs)dZ" % dict(asctime=record.asctime, msecs=record.msecs),
            "aws_request_id": getattr(record, "aws_request_id", "00000000-0000-0000-0000-000000000000"),
            "message": record.message,
            "module": record.module,
            "logger": "lambda_logger_datadog",
            "data": record.__dict__.get("data", {}),
        }
        return json.dumps(j)


def configure_logger(custom_handler=None, level=logging.INFO):
    def factory(f):
        @wraps(f)
        def decorator(*args, **kwargs):
            try:
                # AWS runtime
                event, context = args[:2]
            except ValueError:
                # We might do this when testing, support it
                event = kwargs.get('event')

            logger = logging.getLogger()
            logger.setLevel(level)

            fmtstr = "[%(levelname)s]\t%(asctime)s.%(msecs)dZ\t%(levelno)s\t%(message)s\n"
            datefmtstr = "%Y-%m-%dT%H:%M:%S"
            formatter = DatadogJsonFormatter(fmt=fmtstr, datefmt=datefmtstr)
            # ensure all timestamps are in UTC (aka GMT) timezone
            formatter.converter = time.gmtime

            handler = custom_handler if custom_handler else logging.StreamHandler()
            handler.setFormatter(formatter)

            # Replace the AWS default root handler formatter, not the entire handler,
            # so that stdout and stderr will still be added to CloudWatch
            # (the default handler - LambdaLoggerHandler - does semi-documented magic)
            if len(logger.handlers) > 0:
                logger.handlers[0].setFormatter(formatter)
            else:
                # running locally, not using SAM
                logger.handlers.append(handler)

            # otherwise DEBUG logging exposes decrypted secrets in the logs
            logging.getLogger("botocore.parsers").setLevel(logging.INFO)

            try:
                return f(*args, **kwargs)
            except Exception as e:
                msg = f"{type(e).__name__}: {e}"  # type of error + shortform message
                formatted_exception_traceback = traceback.format_exc()
                logger.error(
                    # logged under "data" field for namespacing, and as a string to prevent
                    # evaluation of the fields by Datadog (which often breaks parsing)
                    msg,
                    extra=dict(data={"lambda_trigger_event": str(event), "traceback": formatted_exception_traceback}),
                )
                sys.exit(1)

        return decorator

    return factory