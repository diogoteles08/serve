import logging
from copy import copy

from ts.torch_handler.base_handler import BaseHandler

logger = logging.getLogger(__name__)


class StreamingHandler(BaseHandler):
    def initialize(self, ctx):
        super().initialize(ctx)

        ctx.cache = {}

        self.canned_replies = ["hello world ", "hello ", "hello ", "hello "]
        logger.info(f"Initialized {self.__class__}")

    def preprocess(self, data):
        logger.info(f"Preprocessing in {self.__class__}")
        logger.info(f"RequestIds: {self.context.request_ids}")
        ready = []
        for req_id, req_data in zip(self.context.request_ids.values(), data):
            if not req_id in self.context.cache:
                logger.info(f"Putting request {req_id} into cache {data}")
                self.context.cache[req_id] = {
                    "stopping_criteria": self.create_stopping_criteria(req_id),
                    "canned_replies": copy(self.canned_replies)
                    + [req_data["body"].decode("utf8")],
                }
            else:
                logger.info(f"Request {req_id} found in cache")
            text = req_data.get("data") or req_data.get("body")
            if isinstance(text, (bytes, bytearray)):
                text = text.decode("utf-8")
            ready.append(text)

        return ready

    def inference(self, data):
        return [
            self.context.cache[i]["canned_replies"].pop()
            for i in self.context.request_ids.values()
        ]

    def postprocess(self, x):
        self.context.stopping_criteria = [
            self.context.cache[i]["stopping_criteria"]
            for i in self.context.request_ids.values()
        ]
        return x

    def create_stopping_criteria(self, req_id):
        class StoppingCriteria(object):
            def __init__(
                self, cache, req_id, max_seq_length=6, stop_token="hello world "
            ):
                self.req_id = req_id
                self.cache = cache
                self.seq_length = max_seq_length
                self.stop_token = stop_token

            def __call__(self, res):
                self.seq_length -= 1
                if self.seq_length == 0 or res == self.stop_token:
                    self.clean_up()
                    return True
                return False

            def clean_up(self):
                del self.cache[self.req_id]

        return StoppingCriteria(
            self.context.cache,
            req_id,
        )