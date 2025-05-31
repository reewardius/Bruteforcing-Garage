# Advanced Bruteforcing

1. Ffuf -> https://github.com/reewardius/bbFuzzing.txt
2. FinderJS -> https://github.com/reewardius/Finder-JS
3. Swagger-Checker -> https://github.com/reewardius/swagger-checker

#### FinderJS

This tool extracts endpoints from JavaScript files. It can be used in two modes: single URL mode and URLs list mode.

## Installation

To install the tool, simply clone the repository:

```bash
git clone https://github.com/ThatNotEasy/Finder-JS.git
```

## Usage

### Single URL Mode

To use the tool in single URL mode, run the following command:

```bash
python3 finder-js.py -u https://example.com/script.js
```

This will extract endpoints from the specified URL and save them to the file `js_endpoints.txt`.

### URLs List Mode

To use the tool in URLs list mode, run the following command:

```bash
python3 finder-js.py -l urls.txt
```

This will extract endpoints from all the URLs in the specified file and save them to the file `js_endpoints.txt`.

The `urls.txt` file should contain a list of URLs, one per line.

### Output

The output of the tool is a text file containing a list of endpoints. Each endpoint is on a new line.

## Options

The tool has the following options:

* `-u`: The URL to extract endpoints from.
* `-l`: The file containing a list of URLs to extract endpoints from.
* `-o`: The output file to save the endpoints to.
* `-p`: Public mode for showing the URLs of each endpoint & showing the function (endpoints/fetch).
* `-t`: The number of threads to use for concurrent processing.

## My Approach
```
rm -rf finder/ && mkdir finder/ && python3 finder-js.py -l js.txt -o endpoints.txt && cat endpoints.txt | grep -Ei 'api|v1|v2|v3|user|admin|internal|debug|data|account|config' > finder/juicyinfo.txt && cat endpoints.txt | grep -E 'http://|https://' > finder/http_links.txt && cat endpoints.txt | grep -E 'create|add|security|reset| update|delete|modify|remove|list|offer|show|trace|allow|disallow|approve|reject|start|stop|set' > finder/interested_api_endpoints.txt
```
Delete Duplicates AND Modify Input Files
```
for f in finder/http_links.txt finder/interested_api_endpoints.txt finder/juicyinfo.txt; do sort -u "$f" -o "$f"; done
sed 's|^/||' finder/juicyinfo.txt
sed 's|^/||' finder/interested_api_endpoints.txt
ffuf -u URL/TOP -w alive_http_services.txt:URL -w juicyinfo.txt:TOP -ac -mc 200 -o fuzz_results.json -fs 0
python3 delete_falsepositives.py -j fuzz_results.json -o fuzz_output1.txt -fp fp_domains1.txt
#################
ffuf -u URL/TOP -w alive_http_services.txt:URL -w interested_api_endpoints.txt:TOP -ac -mc 200 -o fuzz_results.json -fs 0
python3 delete_falsepositives.py -j fuzz_results.json -o fuzz_output2.txt -fp fp_domains2.txt
```

This will extract endpoints from all the URLs in the specified file and save them to the file `js_endpoints.txt`.

#### Get Only Params
```
python3 params-extractor.py -l js.txt --only-params
```
Finally, params save to `params.txt` file (by default)
