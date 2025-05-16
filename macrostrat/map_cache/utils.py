from random import randint

SKU_ID = '01'
TOKEN_VERSION = '1'
base62chars = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'


def construct_sku_token():
    """Construct a session token"""
    randomizer = ''

    for i in range(10):
        randomizer += base62chars[randint(0, len(base62chars)-1)]

    token = "".join([TOKEN_VERSION,SKU_ID,randomizer])
    return token

