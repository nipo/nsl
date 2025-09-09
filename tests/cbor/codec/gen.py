import click
import json

@click.command()
@click.argument("src", type = click.File(mode = "r"))
def convert(src):
    suite = json.load(src)
    for index, element in enumerate(suite):
        hex = element["hex"]
        blob = bytes.fromhex(hex)

        if 'diagnostic' not in element:
            continue
        
        diag = element["diagnostic"]
        diag_text = diag.replace('"', '""')
        print(f"  codec_assert(\"s{index}\", from_hex(\"{blob.hex()}\"), \"{diag_text}\");")
        

if __name__ == "__main__":
    convert()
