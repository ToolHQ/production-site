#!/bin/bash
# Check if pip for Python 3 is installed
if ! command -v pip3 &> /dev/null
then
    echo "pip3 could not be found, installing it..."
    sudo apt update
    sudo apt install python3-pip -y
fi

# Install Python dependencies using pip3
pip3 install elasticsearch pyarrow fastparquet
