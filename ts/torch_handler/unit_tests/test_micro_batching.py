"""
Unit test for MicroBatchHandler class.
"""
import random
import sys
from pathlib import Path

import pytest
from torchvision.models.resnet import ResNet18_Weights

from ts.torch_handler.image_classifier import ImageClassifier
from ts.torch_handler.micro_batching import MicroBatching

from .test_utils.mock_context import MockContext
from .test_utils.model_dir import copy_files, download_model

REPO_DIR = Path(__file__).parents[3]


def read_image_bytes(filename):
    with open(
        filename,
        "rb",
    ) as fin:
        image_bytes = fin.read()
    return image_bytes


@pytest.fixture(scope="module")
def kitten_image_bytes():
    return read_image_bytes(
        REPO_DIR.joinpath(
            "examples/image_classifier/resnet_152_batch/images/kitten.jpg"
        ).as_posix()
    )


@pytest.fixture(scope="module")
def dog_image_bytes():
    return read_image_bytes(
        REPO_DIR.joinpath(
            "examples/image_classifier/resnet_152_batch/images/dog.jpg"
        ).as_posix()
    )


@pytest.fixture(scope="module")
def model_name():
    return "image_classifier"


@pytest.fixture(scope="module")
def model_dir(tmp_path_factory, model_name):
    model_dir = tmp_path_factory.mktemp("image_classifier_model_dir")

    src_dir = REPO_DIR.joinpath("examples/image_classifier/resnet_18/")

    model_url = ResNet18_Weights.DEFAULT.url

    download_model(model_url, model_dir)

    files = {
        "model.py": model_name + ".py",
        "index_to_name.json": "index_to_name.json",
    }

    copy_files(src_dir, model_dir, files)

    sys.path.append(model_dir.as_posix())
    yield model_dir
    sys.path.pop()


@pytest.fixture(scope="module")
def context(model_dir, model_name):

    context = MockContext(
        model_name="mnist",
        model_dir=model_dir.as_posix(),
        model_file=model_name + ".py",
    )
    yield context


@pytest.fixture(scope="module", params=[1, 16, 32])
def handler(context, request):
    handler = ImageClassifier()

    mb_handle = MicroBatching(handler, micro_batch_size=request.param)
    handler.initialize(context)

    handler.handle = mb_handle

    return handler


@pytest.fixture(scope="module", params=[1, 32])
def mixed_batch(kitten_image_bytes, dog_image_bytes, request):
    batch_size = request.param
    labels = [
        "tiger_cat" if random.random() > 0.5 else "golden_retriever"
        for _ in range(batch_size)
    ]
    test_data = []
    for l in labels:
        test_data.append(
            {"data": kitten_image_bytes}
            if l == "tiger_cat"
            else {"data": dog_image_bytes}
        )
    return test_data, labels


def test_handle(context, mixed_batch, handler):
    test_data, labels = mixed_batch
    results = handler.handle(test_data, context)
    assert len(results) == len(labels)
    for l, r in zip(labels, results):
        assert l in r


def test_handle_explain(context, kitten_image_bytes, handler):
    context.explain = True
    test_data = [{"data": kitten_image_bytes, "target": 0}] * 2
    results = handler.handle(test_data, context)
    assert len(results) == 2
    assert results[0]
