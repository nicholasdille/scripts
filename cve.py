#!/usr/bin/python3

import sys
import argparse
import json
import random
import string
import time
import requests
import gzip
import io

class Cve(object):
    @staticmethod
    def decodeCveFromJson(obj):
        if "__type__" in obj and obj["__type__"] == "Cve":
            return Cve(obj["id"], obj["description"], obj["date"])
        return obj

    id: str
    description: str
    date: str
    filters: list

    def __init__(self, id, description, date):
        self.id = id
        self.description = description
        self.date = date

    def toJson(self) -> str:
        return f'{{"id": "{self.id}", "description": "{self.description}", "date": "{self.date}"}}'

class CveSource:
    name: str
    sources = []
    @staticmethod
    def getParameterDefinition() -> list:
        return []
    def get(self) -> list:
        pass
    def setParameters(*params):
        pass

class CveFilter:
    name: str
    filters = []
    @staticmethod
    def getParameterDefinition() -> list:
        return []
    def filter(self, cves: list) -> list:
        pass
    def setParameters(*params):
        pass

class CveTarget:
    name: str
    filters = []
    @staticmethod
    def getParameterDefinition() -> list:
        return []
    def put(self, cves: list):
        pass
    def setParameters(*params):
        pass

class NistSource(CveSource):
    name = "nist"
    @staticmethod
    def getParameterDefinition() -> list:
        return []
    # https://nvd.nist.gov/vuln/data-feeds
    metadata_url = "https://nvd.nist.gov/feeds/json/cve/1.1/nvdcve-1.1-recent.meta"
    recent_feed_url = "https://nvd.nist.gov/feeds/json/cve/1.1/nvdcve-1.1-recent.json.gz"
    def get(self) -> list:
        cves = []
        response = requests.get(self.recent_feed_url)
        compressed_file = io.BytesIO(response.content)
        decompressed_file = gzip.GzipFile(fileobj=compressed_file)
        #wrapper = io.TextIOWrapper(decompressed_file)
        items = json.loads(decompressed_file.read())
        for item in items["CVE_Items"]:
            for description_obj in item["cve"]["description"]["description_data"]:
                if description_obj["lang"] == "en":
                    description = description_obj["value"]
                    break
            cves.append(Cve(
                item["cve"]["CVE_data_meta"]["ID"],
                description,
                item["publishedDate"]
            ))
        return cves

class DummySource(CveSource):
    name = "dummy"
    @staticmethod
    def getParameterDefinition() -> list:
        return [
            {
                "name":    "count",
                "help":    "How many CVE items to return",
                "default": 3
            },
            {
                "name":    "keywords",
                "help":    "Keywords to add to description",
                "default": "foo,bar,blarg"
            }
        ]
    count: int
    keywords: list
    def get(self) -> list:
        time_format = "%Y-%m-%dT%H:%MZ"
        start_time = time.mktime(time.strptime("2021-01-01T00:00Z", time_format))
        end_time   = time.mktime(time.strptime("2021-12-31T23:59Z", time_format))
        cves = []
        print(f"Have {len(self.keywords)} keywords")
        for i in range(self.count):
            timestamp = time.strftime(
                time_format,
                time.localtime(
                    start_time + random.random() * (end_time - start_time)
                )
            )
            description = "".join(random.choices(string.ascii_lowercase + string.ascii_uppercase + string.digits, k=10)) + \
                " " + \
                self.keywords[random.randint(0, len(self.keywords) - 1)] + \
                " " + \
                "".join(random.choices(string.ascii_lowercase + string.ascii_uppercase + string.digits, k=10))
            cves.append(
                json.loads(
                    '{'\
                        '"__type__":    "Cve",'\
                        f'"id":          "CVE-2021-{random.randint(0, 99999)}",'\
                        f'"description": "{description}",'\
                        f'"date":        "{timestamp}"'\
                    '}',
                    object_hook=Cve.decodeCveFromJson
                )
            )
        return cves
    def setParameters(self, *params):
        self.count = int(params[0])
        self.keywords = params[1].split(",")

class KeywordFilter(CveFilter):
    name = "keyword"
    @staticmethod
    def getParameterDefinition() -> list:
        return [
            {
                "name": "term",
                "help": "Term to filter for"
            }
        ]
    term: str
    def filter(self, cves: list) -> list:
        print(f"Returning items matching {self.term}")
        filtered_cves = []
        if self.term == None:
            print(f"ERROR: Please provide term for keyword filter.")
        else:
            for cve in cves:
                if self.term in cve.description:
                    filtered_cves.append(cve)
        return filtered_cves
    def setParameters(self, *params):
        self.term = params[0]

class NoFilter(CveFilter):
    name = "none"
    def filter(self, cves: list) -> list:
        return cves

class FirstItemsFilter(CveFilter):
    name = "first"
    @staticmethod
    def getParameterDefinition() -> list:
        return [
            {
                "name": "n",
                "help": "How many items from the top",
                "default": 1
            }
        ]
    number: int
    def filter(self, cves: list) -> list:
        print(f"Returning first {self.number} items")
        return cves[0:self.number]
    def setParameters(self, *params):
        self.number = int(params[0])

class GitLabIssuesTarget(CveTarget):
    name = "gitlab_issues"
    def put(self, cves: list):
        print("GitLabIssuesTarget")

class ConsoleTarget(CveTarget):
    name = "console"
    def put(self, cves: list):
        for cve in cves:
            print(cve.toJson())

CveSource.sources = [
    NistSource,
    DummySource
]
source_keys = []
for source in CveSource.sources:
    source_keys.append(source.name)

CveFilter.filters = [
    NoFilter,
    FirstItemsFilter,
    KeywordFilter
]
filter_keys = []
for filter in CveFilter.filters:
    filter_keys.append(filter.name)

targets = {
    "gitlab_issues": GitLabIssuesTarget,
    "console":       ConsoleTarget
}
target_keys = list(targets.keys())

parser = argparse.ArgumentParser(prog="cve", description='Process CVEs', formatter_class=argparse.ArgumentDefaultsHelpFormatter)
parser.add_argument("--source", "-s", choices=source_keys, default=source_keys[0],   required=False,            help="Where to get CVEs")
parser.add_argument("--filter", "-f", choices=filter_keys, default=[filter_keys[0]], required=False, nargs="*", help="Which CVEs to process")
parser.add_argument("--target", "-t", choices=target_keys, default=target_keys[0],   required=False,            help="Where to put CVEs")

for source in CveSource.sources:
    source_name = source.name
    for param in source.getParameterDefinition():
        parser.add_argument(f'--{source_name}-{param["name"]}', help=f'{param["help"]}')

for filter in CveFilter.filters:
    filter_name = filter.name
    for param in filter.getParameterDefinition():
        parser.add_argument(f'--{filter_name}-{param["name"]}', help=f'{param["help"]}')

args = parser.parse_args()
#print(f"args: {vars(args)}")

def process_source(source: CveSource) -> list:
    if not issubclass(type(source), CveSource):
        print(f"ERROR: Source must be of type CveSource but is {type(source)}.")
        sys.exit(1)
    return source.get()

def process_filter(filter: CveFilter, cves: list):
    if not issubclass(type(filter), CveFilter):
        print(f"ERROR: Filter must be of type CveFilter but is {type(filter)}")
        sys.exit(1)
    return filter.filter(cves)

def process_target(target: CveTarget, cves: list):
    if not issubclass(type(target), CveTarget):
        print(f"ERROR: Target must be of type CveTarget but is {type(target)}")
        sys.exit(1)
    target.put(cves)

#source = sources[args.source]()
source_name = args.source
for source_type in CveSource.sources:
    if source_type.name == source_name:
        source = source_type()
        break
print(f"Using source of type {type(source)}")
params = []
for param in source.getParameterDefinition():
    arg_name = f'{source_name}_{param["name"]}'
    arg = vars(args)[arg_name] or param["default"]
    params.append(arg)
source.setParameters(*params)
cves = process_source(source)
print(f"cves is type {type(cves)} of length {len(cves)}")

print(f"args.filter is type {type(args.filter)}")
for filter_name in args.filter:
    print(f"Processing filter {filter_name}")
    for filter_type in CveFilter.filters:
        if filter_type.name == filter_name:
            filter = filter_type()
            break
    print(f"Using filter of type {type(filter)}")
    params = []
    for param in filter.getParameterDefinition():
        arg_name = f'{filter_name}_{param["name"]}'
        arg = vars(args)[arg_name] or param["default"]
        params.append(arg)
    filter.setParameters(*params)
    cves = process_filter(filter, cves)
    print(f"cves is type {type(cves)} of length {len(cves)}")

target = targets[args.target]()
print(f"Using target of type {type(target)}")
process_target(target, cves)
