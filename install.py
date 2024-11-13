import os
import subprocess

current_directory = os.getcwd()

def install_pyenv():
    script_path = current_directory + '/bin/install_pyenv.sh'
    print(script_path)
    result = subprocess.run([script_path], capture_output=True, text= True)
    exit()
    print("STDOUT:", result.stdout)
    print("STDERR:", result.stderr)

install_pyenv()
