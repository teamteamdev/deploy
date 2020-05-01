from werkzeug.wsgi import ClosingIterator
from werkzeug.local import Local, release_local
import logging


logger = logging.getLogger(__name__)


def run_callback(cb):
    try:
        cb()
    except Exception as e:
        logger.error("Error in after response callback", exc_info=e)


class AfterResponse:
    def __init__(self, app):
        self.callbacks = []
        self.local = Local()

        old_app = app.wsgi_app
        def new_wsgi_app(environ, after_response):
            iterator = old_app(environ, after_response)
            return ClosingIterator(iterator, [self._run])
        app.wsgi_app = new_wsgi_app

    def _run(self):
        if hasattr(self.local, "callbacks"):
            for cb in reversed(self.local.callbacks):
                run_callback(cb)
            # We clean local callbacks manually. LocalManager will do it too soon; we use
            # them after the response is sent.
            release_local(self.local)

        for cb in reversed(self.callbacks):
            run_callback(cb)

    def always(self, callback):
        self.callbacks.append(callback)
        return callback

    def once(self, callback):
        if not hasattr(self.local, "callbacks"):
            self.local.callbacks = []
        self.local.callbacks.append(callback)
        return callback
