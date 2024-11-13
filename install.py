import subprocess

def install_bash_it():
    subprocess.run(["./home/.bash-it/install.sh"], capture_output= True)

install_bash_it()
