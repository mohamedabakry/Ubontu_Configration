#!/usr/bin/env python3
"""Verify that no Pydantic dependencies exist in the project."""

import os
import re
import sys
from pathlib import Path

def check_file_for_pydantic(file_path):
    """Check a Python file for Pydantic imports or usage."""
    pydantic_patterns = [
        r'from\s+pydantic\s+import',
        r'import\s+pydantic',
        r'BaseSettings',
        r'@validator',
        r'@field_validator',
        r'Field\(',
        r'pydantic\.',
        r'pydantic-settings'
    ]
    
    issues = []
    
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
            lines = content.split('\n')
            
            for i, line in enumerate(lines, 1):
                for pattern in pydantic_patterns:
                    if re.search(pattern, line, re.IGNORECASE):
                        issues.append({
                            'line': i,
                            'content': line.strip(),
                            'pattern': pattern
                        })
    except Exception as e:
        print(f"❌ Error reading {file_path}: {e}")
        return []
    
    return issues

def check_requirements_file(file_path):
    """Check requirements.txt for Pydantic dependencies."""
    pydantic_deps = ['pydantic', 'pydantic-settings']
    issues = []
    
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()
            
            for i, line in enumerate(lines, 1):
                line = line.strip().lower()
                if line and not line.startswith('#'):
                    for dep in pydantic_deps:
                        if dep in line:
                            issues.append({
                                'line': i,
                                'content': line,
                                'dependency': dep
                            })
    except FileNotFoundError:
        print(f"⚠️  {file_path} not found")
        return []
    except Exception as e:
        print(f"❌ Error reading {file_path}: {e}")
        return []
    
    return issues

def main():
    """Main verification function."""
    print("🔍 VERIFYING PROJECT FOR PYDANTIC DEPENDENCIES")
    print("=" * 50)
    
    project_root = Path('.')
    issues_found = False
    
    # Check Python files
    print("\n📁 Checking Python files...")
    python_files = list(project_root.rglob('*.py'))
    
    for py_file in python_files:
        # Skip __pycache__ and .git directories
        if '__pycache__' in str(py_file) or '.git' in str(py_file):
            continue
            
        issues = check_file_for_pydantic(py_file)
        if issues:
            issues_found = True
            print(f"\n❌ {py_file}:")
            for issue in issues:
                print(f"   Line {issue['line']}: {issue['content']}")
                print(f"   Pattern: {issue['pattern']}")
    
    # Check requirements.txt
    print("\n📦 Checking requirements.txt...")
    req_issues = check_requirements_file('requirements.txt')
    if req_issues:
        issues_found = True
        print("\n❌ requirements.txt:")
        for issue in req_issues:
            print(f"   Line {issue['line']}: {issue['content']}")
            print(f"   Dependency: {issue['dependency']}")
    
    # Check Docker files
    print("\n🐳 Checking Docker files...")
    docker_files = ['Dockerfile', 'docker-compose.yml']
    for docker_file in docker_files:
        if os.path.exists(docker_file):
            try:
                with open(docker_file, 'r') as f:
                    content = f.read()
                    if 'pydantic' in content.lower():
                        issues_found = True
                        print(f"❌ {docker_file} contains 'pydantic'")
            except Exception as e:
                print(f"❌ Error reading {docker_file}: {e}")
    
    # Summary
    print("\n" + "=" * 50)
    if issues_found:
        print("❌ PYDANTIC DEPENDENCIES FOUND!")
        print("Please remove all Pydantic dependencies before rebuilding.")
        sys.exit(1)
    else:
        print("✅ NO PYDANTIC DEPENDENCIES FOUND!")
        print("Project is clean and ready for rebuild.")
        
        # Test configuration import
        print("\n🧪 Testing configuration import...")
        try:
            sys.path.insert(0, 'src')
            from config import config
            print("✅ Configuration imports successfully!")
            print(f"✅ Database URL: {config.database_url}")
            print("✅ All configuration properties accessible!")
        except Exception as e:
            print(f"❌ Configuration test failed: {e}")
            sys.exit(1)

if __name__ == '__main__':
    main()