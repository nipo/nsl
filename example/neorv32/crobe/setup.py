from setuptools import setup, find_namespace_packages

setup(
    name = "crobe_neorv32_example",
    version = "0.1",
    description = "Crobe plugin for NeoRV32 example",
    author = "Nicolas Pouillon",
    author_email = "nipo@ssji.net",
    license = "BSD",
    classifiers = [
        "Development Status :: 4 - Beta",
        "Programming Language :: Python",
    ],
    use_2to3 = False,
    packages = find_namespace_packages(include=['crobe_plugin.*']),
)
