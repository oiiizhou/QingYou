"""用标准库检查内置 Office 模板，构建不依赖 Python 第三方包。"""
from pathlib import Path
from xml.etree import ElementTree
from zipfile import ZipFile
import struct

root = Path(__file__).resolve().parent.parent / "Resources" / "Templates"
required = {"Blank.docx": "word/document.xml", "Blank.xlsx": "xl/workbook.xml", "Blank.pptx": "ppt/presentation.xml"}
for name, main_part in required.items():
    with ZipFile(root / name) as archive:
        assert archive.testzip() is None, f"{name}: ZIP 校验失败"
        assert main_part in archive.namelist(), f"{name}: 缺少主文档"
        for item in archive.namelist():
            if item.endswith((".xml", ".rels")):
                ElementTree.fromstring(archive.read(item))
    print(f"✓ {name} 结构校验通过")


def compound_streams(path):
    """读取这些小型 CFB 模板的目录，避免把 ZIP 改后缀后误当成旧版 Office 文件。"""
    data = path.read_bytes()
    assert data[:8] == bytes.fromhex("d0cf11e0a1b11ae1"), f"{path.name}: 不是复合二进制文档"
    sector_size = 1 << struct.unpack_from("<H", data, 30)[0]
    assert sector_size in (512, 4096)
    def sector(index):
        start = (index + 1) * sector_size
        value = data[start:start + sector_size]
        assert len(value) == sector_size, f"{path.name}: 扇区超出文件范围"
        return value
    fat_count = struct.unpack_from("<I", data, 44)[0]
    assert fat_count <= 109, "内置空白模板不应需要扩展 DIFAT"
    fat_sectors = struct.unpack_from("<109I", data, 76)[:fat_count]
    fat = []
    for index in fat_sectors:
        fat.extend(struct.unpack("<" + "I" * (sector_size // 4), sector(index)))
    directory = bytearray()
    current = struct.unpack_from("<I", data, 48)[0]
    seen = set()
    while current != 0xfffffffe:
        assert current not in seen and current < len(fat), "目录链损坏"
        seen.add(current)
        directory.extend(sector(current))
        current = fat[current]
    streams = set()
    for offset in range(0, len(directory), 128):
        name_length = struct.unpack_from("<H", directory, offset + 64)[0]
        if directory[offset + 66] == 2:
            assert 2 <= name_length <= 64
            streams.add(directory[offset:offset + name_length - 2].decode("utf-16le"))
    return streams


for name, stream in {"Blank.doc": "WordDocument", "Blank.xls": "Workbook", "Blank.ppt": "PowerPoint Document"}.items():
    assert stream in compound_streams(root / name), f"{name}: 缺少文档主数据流"
    print(f"✓ {name} 二进制结构校验通过")
