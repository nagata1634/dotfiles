import json
import pathlib as Path
import subprocess

def package_install(package_list, dict_packages):
    for groups_package in package_list:
        search_package = [item for item in dict_packages['packages'] if item['name'] == groups_package]
        for dist_package in search_package:

            if dist_package['version'] != 'latest':
                package = dist_package['name'] + '=' + dist_package['version']
            else:
                package = dist_package['name']
            try:
                subprocess.run(['sudo','apt','install',package], capture_output=True, text=True)
            except subprocess.CalledProcessError as e:
                print(f'Errer : {e}')
                return False

    return True

def open_packages(filepath):
    try:
        with open(filepath, 'r') as file:
            packages = json.load(file)
    except FileNotFoundError:
        print('ファイルが見つかりませんでした')
        packages = {}
    
    except PermissionError:
        print('ファイルへのアクセス権限がありません。')
        packages = {}
    
    if packages:
    
        get_dependencies_by_group = packages['groups'].copy()
    
        for key, value in get_dependencies_by_group.items():
            while True:
                input_value = input(f'{key}関連パッケージをインストールしますか？[y/n] : ')
                if input_value.lower() == 'y':
                    package_install(value, packages)
                    pass
                elif input_value.lower() == 'n':
                    pass
                else:
                    print('入力が正しくありません')
                    continue
                break

if __name__ == "__main__":
    open_packages('./setting/packages_install.json')
