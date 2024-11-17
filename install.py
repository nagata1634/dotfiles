import subprocess
from pathlib import Path

# 設定ファイルのマッピング
config_files = {
    '~/dotfiles/home/.bashrc': '~/.bashrc',
    '~/dotfiles/config/nvim/init.lua': '~/.config/nvim/init.lua'
}

package_lists = {
    'foundation': ['neovim', 'git'],
    'pyenv': ['build-essential', 'libssl-dev', 'zlib1g-dev', 'libbz2-dev', 'libreadline-dev',' libsqlite3-dev', 'curl', 'libncursesw5-dev', 'xz-utils', 'tk-dev', 'libxml2-dev', 'libxmlsec1-dev', 'libffi-dev', 'liblzma-dev'],
}

# ホームディレクトリのパスを取得
home = Path.home()

def create_symlinks(config_files):
    for source, dest in config_files.items():
        source_path = Path(source).expanduser()
        dest_path = Path(dest).expanduser()
#       dest_patfoundationh = home / dest

        # 親ディレクトリが存在しない場合は作成
        dest_path.parent.mkdir(parents=True, exist_ok=True)

        # シンボリックリンクの作成
        print('シンボリックリンクを作成します...')
        try:
            dest_path.symlink_to(source_path)
            print(f"Created symlink: {dest_path} -> {source_path}")
        except FileExistsError:
            print(f"Symlink already exists: {dest_path}")
        except Exception as e:
            print(f"Error creating symlink {dest_path}: {e}")

def install_package(package_lists):

    # パッケージリストをアップデート
    print('パッケージリストをアップデートしています...')
    try:
        subprocess.run(['sudo', 'apt', 'update'], capture_output=True, text=True)
    except subprocess.CalledProcessError as e:
        print(f'パッケージリストのアップデートに失敗しました : {e.stderr}')
        print('プログラムを修了します')
        exit()

    for source, package_list in package_lists.items():
        # パッケージを順番にインストールする
        print(f'{source}に関連するパッケージをインストールします')

        for package in package_list:
            print(f'{package}をインストール中...')
            try:
                subprocess.run(['sudo', 'apt', 'install', package], capture_output=True, text=True)
            except subprocess.CalledProcessError as e:
                print(f'パッケージのインストールに失敗しました : {e.stderr}')

    print('パッケージのインストールが正常に終わりました')

if __name__ == "__main__":
    create_symlinks(config_files)
    install_package(package_lists)
