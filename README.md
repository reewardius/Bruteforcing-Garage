### Bruteforcing Advanced Bruteforcing

1. Ffuf -> https://github.com/reewardius/bbFuzzing.txt
2. FinderJS -> https://github.com/reewardius/Finder-JS
3. Swagger-Checker -> https://github.com/reewardius/swagger-checker

#### AutoFinder
```bash
[root@ip-10-0-0-147 Bruteforcing-Garage]# bash autofinder.sh -h
Usage:
  autofinder.sh -d <domain>          # For single domain
  autofinder.sh -f <file>            # For multiple domains from file

Examples:
  autofinder.sh -d target.com
  autofinder.sh -f domains.txt

Description:
  Script performs complete subdomain reconnaissance including:
  - Subdomain discovery (subfinder)
  - Live service check (httpx)
  - JS file extraction (getJS)
  - Endpoint discovery (finder-js.py)
  - Fuzzing (ffuf)
  - Vulnerability scanning (nuclei)
```
![image](https://github.com/user-attachments/assets/ce369a41-904e-4db6-a15d-246785f5b8d8)

#### Swagger-Checker
```bash
git clone https://github.com/reewardius/swagger-checker && cd swagger-checker && \
subfinder -d target.com -all -silent -o subs.txt && \
naabu -l subs.txt -s s -tp 100 -ec -c 50 -o naabu.txt && \
httpx -l naabu.txt -rl 500 -t 200 -o alive_http_services.txt && \
python3 generate.py -i alive_http_services.txt -o alive_http_services_advanced.txt && \
nuclei -l alive_http_services_advanced.txt -id openapi,swagger-api -o swagger_endpoints.txt -rl 1000 -c 100 && \
python3 swagger_checker_threads.py -t 100
```

#### Get Only Params
```bash
python3 params-extractor.py -l js.txt --only-params
```
Finally, params save to `params.txt` file (by default)



