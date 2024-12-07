import json
from pathlib import Path
import subprocess

SETTING_FILE = Path('./setting/packages_install.json')

if not SETTING_FILE.exists():
    print(f'{SETTING_FILE}が見つかりません')
    exit()

def package_installer(install_package_list, package_version_list):
    # インストールするパッケージを入れるリスト
    install_commands = []
    # インストールするパッケージをループさせる
    for package_name in install_package_list:
        # パッケージのバージョンを確認する
        for package_version in package_version_list:
            if package_version['name'] == package_name:
                if package_version['version'] == 'latest':
                # 最新バージョンを指定
                    install_commands.append(package_name)
                else:
                # バージョンを指定する
                    install_commands.append(f'{package_name}={package_version['version']}')


    # パッケージをインストール
    result = subprocess.run(['sudo','apt','install', '-y'] + install_commands, capture_output=True, text=True)
    if result.returncode != 0:
        print(f'Error: {result.stderr}')


def package_installer1(install_package_list, package_version_list):
    # パッケージの名前とバージョンの辞書を作る
    package_version_map = {pkg['name']: pkg['version'] for pkg in package_version_list.items()}
    # インストールするパッケージを入れるリスト
    install_commands = []
    # インストールするパッケージをループさせる
    for package_name in install_package_list:
        # 検索
        if package_name in package_version_map:
            version = package_version_map[package_name]
            if version == 'latest':
                # 最新バージョンを指定
                install_commands.append(package_name)
            else:
                # バージョンを指定
                install_commands.append(f'{package_name}={version}')
        else:
            print(f'{package_name}のバージョン情報が見つかりませんでした。スキップします。')

    # パッケージをインストール
    result = subprocess.run(['sudo','apt','install', '-y'] + install_commands, capture_output=True, text=True)
    if result.returncode != 0:
        print(f'Error: {result.stderr}')

def load_packages_from_file(file_path):
    # ファイルを読み込みます
    try:
        with open(file_path, 'r') as file:
            road_dict = json.load(file)
    except FileNotFoundError:
        print('ファイルが見つかりませんでした')
        road_dict = {}
    except PermissionError:
        print('ファイルへのアクセス権限がありません。')
        road_dict = {}
    except json.JSONDecodeError:
        print('jsonファイルに誤りが存在します')
        road_dict = {}

    # 読み込んだJSONファイルをdictに変換して返します
    return road_dict

def confirm_action(packages_data):
    # packages_dataが存在するか確認する
    if not packages_data:
        print('終了します')
        exit()
    else:
        package_set = set()
        # 辞書型から'groups'キーの値を取り出す
        groups_to_install = packages_data['groups'].copy()
        # 質問を開始
        for key, value in groups_to_install.items():
            input_value = input(f'{key}関連パッケージをインストールしますか？[y/n] : ')
            if input_value.lower() == 'y':
                package_set.update(set(value))
            elif input_value.lower() == 'n':
                pass
            else:
                print('入力が正しくありません')
                continue
        return package_set

if __name__ == "__main__":
#    install_packages_from_file(SETTING_FILE)

    package_dict = load_packages_from_file(SETTING_FILE)

    package_set = confirm_action(package_dict)

    package_installer(package_set, package_dict['packages'])
    package_installer1(package_set, package_dict['packages'])
    subprocess.run(['bash', '-c', 'curl -s "https://get.sdkman.io" | bash'], capture_output=True, text=True)
