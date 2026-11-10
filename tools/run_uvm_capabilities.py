#!/usr/bin/env python3
"""Compatibility entry point for the common UVM capability runner."""
import sys
from run import main

if __name__ == '__main__':
    sys.exit(main(['test-uvm-smoke', *sys.argv[1:]]))
