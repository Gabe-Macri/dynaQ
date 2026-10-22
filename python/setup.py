from setuptools import setup, find_packages

setup(
    name="dynaq",
    version="1.0.0b2",
    description="dynaQ Professional Audio Backend SDK & Acoustic Optimization Engine",
    author="dynaQ Audio Team",
    packages=find_packages(),
    python_requires=">=3.8",
    entry_points={
        "console_scripts": [
            "dynaq-backend = dynaq.cli:main",
        ],
    },
    classifiers=[
        "Topic :: Multimedia :: Sound/Audio",
        "Operating System :: MacOS",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
    ],
)

