#!/usr/bin/env bash

echo "Creating sdist package..."
python setup.py sdist
echo " "
echo "Creating wheel package..."
python setup.py bdist_wheel