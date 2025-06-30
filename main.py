#!/usr/bin/env python3
"""
Route Table Collector - Main Entry Point

This is the main entry point for the routing table collector application.
It provides a convenient way to run the CLI without using the module syntax.
"""

import sys
import os

# Add the src directory to the Python path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'src'))

from src.cli import cli

if __name__ == '__main__':
    cli()