import json

try:
    with open('setting.json', 'r') as f:
        datas = json.load(f)
        print(type(datas))

        for key, value in datas.items():
            print(f'{key}, {type(value)}')

except FileNotFoundError:
    print('ファイルが存在しません')
except json.JSONDecodeError:
    print('jsonファイルが読み取れません。: ')

