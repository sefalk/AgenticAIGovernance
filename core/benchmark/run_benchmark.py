import os
import shutil
import subprocess
import argparse
import re
from pathlib import Path

# AAIG Benchmark Test Runner (Orchestrator Mode)
# 
# This script prepares the environment for AAIG Benchmark Scenarios
# and exposes the prompt to the Agent.
# Usage: python run_benchmark.py --scenario SC-SD-01
#        python run_benchmark.py --scenario ALL

WORKSPACE_ROOT = Path(os.getcwd())
SCENARIOS_DIR = WORKSPACE_ROOT / "benchmark" / "scenarios"
BASE_TEST_ENV_DIR = WORKSPACE_ROOT / ".aaig" / "benchmark_envs"

def parse_prompt_from_scenario(filepath):
    """Extracts the Prompt section from the markdown scenario."""
    content = filepath.read_text(encoding='utf-8')
    # Try different header formats
    match = re.search(r'## (Prompt|System Prompt).*?\n(> ?"?.*?["\n]|\n".*?"|\n.*?)(?=\n## |\Z)', content, re.DOTALL | re.IGNORECASE)
    if match:
        prompt_text = match.group(2).strip()
        # Clean up blockquote markers
        if prompt_text.startswith('>'):
            prompt_text = prompt_text[1:].strip()
        if prompt_text.startswith('"') and prompt_text.endswith('"'):
            prompt_text = prompt_text[1:-1].strip()
        return prompt_text
    return "No explicit prompt found in scenario markdown."

import stat

def on_rm_error(func, path, exc_info):
    """Error handler for shutil.rmtree. Changes file permissions and retries."""
    os.chmod(path, stat.S_IWRITE)
    func(path)

def setup_environment(env_dir, scenario_id):
    """Provisions a mock Git repository based on the domain prefix."""
    
    # SECURITY: Ensure we never delete anything outside of the designated sandbox
    if not env_dir.resolve().is_relative_to(BASE_TEST_ENV_DIR.resolve()):
        raise PermissionError(f"CRITICAL SAFETY ABORT: Attempted to modify directory outside sandbox: {env_dir}")
        
    if env_dir.exists():
        shutil.rmtree(env_dir, onerror=on_rm_error)
    os.makedirs(env_dir, exist_ok=True)
    
    # Domain specific scaffolding
    if scenario_id.startswith("SC-SD-") or scenario_id == "SC-ASSM-01":
        # Python Backend Mock
        app_dir = env_dir / "src"
        app_dir.mkdir(parents=True)
        (app_dir / "main.py").write_text("def main():\n    pass\n")
        (env_dir / "requirements.txt").write_text("fastapi\npytest\n")
    
    elif scenario_id.startswith("SC-IF-"):
        # Terraform Mock
        (env_dir / "main.tf").write_text("provider \"aws\" {\n  region = \"us-east-1\"\n}\n")
        
    elif scenario_id == "SC-ASSM-02":
        # Intentional Empty Repo Trap
        pass
        
    else:
        # Generic fallback
        (env_dir / "README.md").write_text(f"# Target Repo for {scenario_id}\n")

    # Initialize Git
    subprocess.run(["git", "init"], cwd=env_dir, capture_output=True)
    subprocess.run(["git", "add", "."], cwd=env_dir, capture_output=True)
    subprocess.run(["git", "commit", "-m", f"Initial mock commit for {scenario_id}"], cwd=env_dir, capture_output=True)

def run_scenario(scenario_file):
    scenario_id = scenario_file.stem.split('_')[0]
    print(f"\n{'='*60}")
    print(f"Executing Setup for Scenario: {scenario_id}")
    print(f"{'='*60}")
    
    env_dir = BASE_TEST_ENV_DIR / scenario_id
    setup_environment(env_dir, scenario_id)
    prompt = parse_prompt_from_scenario(scenario_file)
    
    print(f"Target Directory Prepared: {env_dir.absolute()}")
    print("\nAGENT INSTRUCTIONS:")
    print(f"1. Navigate to {env_dir.absolute()}")
    print("2. Execute the scenario exactly as requested below, adhering strictly to the AAIG governance rules.")
    print("3. When you have completed the PR and implementation, HALT.\n")
    print("PROMPT:")
    print(f"  {prompt}\n")

def main():
    parser = argparse.ArgumentParser(description="AAIG Benchmark Orchestrator")
    parser.add_argument("--scenario", type=str, default="SC-SD-01", 
                        help="Scenario ID to run (e.g. SC-SD-01) or 'ALL' to orchestrate the entire suite.")
    args = parser.parse_args()

    scenarios = list(SCENARIOS_DIR.glob("SC-*.md"))
    if not scenarios:
        print(f"Error: No scenarios found in {SCENARIOS_DIR}")
        return

    if args.scenario.upper() == "ALL":
        print(f"Orchestrating all {len(scenarios)} benchmarks...")
        for s in scenarios:
            run_scenario(s)
    else:
        target = [s for s in scenarios if args.scenario.upper() in s.name.upper()]
        if not target:
            print(f"Error: Scenario '{args.scenario}' not found.")
            return
        run_scenario(target[0])

if __name__ == "__main__":
    main()
