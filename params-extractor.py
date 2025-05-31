import argparse
import requests
import re
import json
from concurrent.futures import ThreadPoolExecutor
from colorama import Fore, Style

EndPoints = []
Parameters = []

def is_in_array(element, arr):
    return element in arr

def is_valid(stringo):
    invalid_chars = ["$", "#", "|", "\\", "?", "(", ")", "[", "]", "{", "}", ",", "<", ":", "*", ">", "\n", "./", "//", ".svg", ".png", ".jpg", ".ico"]
    return not any(char in stringo for char in invalid_chars) and len(stringo) > 1

def extract_parameters(content):
    """Extract various types of parameters from JavaScript content"""
    params = set()
    
    # Extract URL parameters (query string parameters)
    url_params = re.findall(r'[?&]([a-zA-Z_][a-zA-Z0-9_]*)\s*=', content)
    params.update(url_params)
    
    # Extract form parameters
    form_params = re.findall(r'name\s*=\s*["\']([^"\']+)["\']', content)
    params.update(form_params)
    
    # Extract JSON object keys that look like parameters
    json_params = re.findall(r'["\']([a-zA-Z_][a-zA-Z0-9_]*)["\']:\s*["\']?[^,}]+["\']?', content)
    params.update(json_params)
    
    # Extract function parameters
    func_params = re.findall(r'function\s+\w*\s*\(([^)]*)\)', content)
    for param_list in func_params:
        if param_list.strip():
            individual_params = [p.strip() for p in param_list.split(',')]
            for param in individual_params:
                # Clean parameter name (remove default values, destructuring, etc.)
                clean_param = re.sub(r'\s*=.*$', '', param)  # Remove default values
                clean_param = re.sub(r'[{}[\]]', '', clean_param)  # Remove destructuring brackets
                clean_param = clean_param.strip()
                if clean_param and re.match(r'^[a-zA-Z_][a-zA-Z0-9_]*$', clean_param):
                    params.add(clean_param)
    
    # Extract arrow function parameters
    arrow_params = re.findall(r'(?:const|let|var)?\s*(?:\(([^)]*)\)|([a-zA-Z_][a-zA-Z0-9_]*))\s*=>', content)
    for param_tuple in arrow_params:
        param_list = param_tuple[0] if param_tuple[0] else param_tuple[1]
        if param_list:
            individual_params = [p.strip() for p in param_list.split(',')]
            for param in individual_params:
                clean_param = re.sub(r'\s*=.*$', '', param).strip()
                if clean_param and re.match(r'^[a-zA-Z_][a-zA-Z0-9_]*$', clean_param):
                    params.add(clean_param)
    
    # Extract object destructuring parameters
    destructuring_params = re.findall(r'\{\s*([^}]+)\s*\}', content)
    for param_group in destructuring_params:
        individual_params = [p.strip() for p in param_group.split(',')]
        for param in individual_params:
            # Handle aliasing (e.g., {name: userName})
            if ':' in param:
                param = param.split(':')[0].strip()
            if re.match(r'^[a-zA-Z_][a-zA-Z0-9_]*$', param):
                params.add(param)
    
    # Extract XMLHttpRequest and fetch parameters
    xhr_params = re.findall(r'\.setRequestHeader\s*\(\s*["\']([^"\']+)["\']', content)
    params.update(xhr_params)
    
    # Extract common API parameter patterns
    api_params = re.findall(r'["\']([a-zA-Z_][a-zA-Z0-9_]*)["\']:\s*(?:req\.(?:body|query|params)\.)?[a-zA-Z_][a-zA-Z0-9_]*', content)
    params.update(api_params)
    
    return list(params)

def extract_all_urls(content):
    urls = set()
    href_links = re.findall(r'href=["\'](https?://[^"\']+)["\']', content)
    urls.update(href_links)
    
    a_links = re.findall(r'<a [^>]*href=["\'](https?://[^"\']+)["\'][^>]*>', content)
    urls.update(a_links)

    src_links = re.findall(r'src=["\'](https?://[^"\']+)["\']', content)
    urls.update(src_links)

    endpoints = re.findall(r'\"/[^"]+\"', content)
    for endpoint in endpoints:
        current_endpoint = endpoint[2:-1]
        if is_valid(current_endpoint) and not is_in_array(current_endpoint, EndPoints):
            EndPoints.append(current_endpoint)
            urls.add(current_endpoint)

    try:
        json_data = json.loads(content)
        json_urls = [url for url in find_urls_in_json(json_data)]
        urls.update(json_urls)
    except json.JSONDecodeError:
        pass

    return list(urls)

def find_urls_in_json(data):
    if isinstance(data, dict):
        for key, value in data.items():
            if key.lower() == 'url':
                yield value
            elif isinstance(value, (dict, list)):
                yield from find_urls_in_json(value)
    elif isinstance(data, list):
        for item in data:
            yield from find_urls_in_json(item)

def gimme_js_link(js_url, output, activation_flag, only_params=False):
    try:
        output_file = 'params.txt' if only_params else output
        success_file = 'success_params.txt' if only_params else 'success.txt'
        
        with open(output_file, 'a') as my_output, open(success_file, 'a') as success_output:
            headers = {"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:109.0) Gecko/20100101 Firefox/109.0"}
            response = requests.get(js_url, headers=headers, timeout=7)
            if response.status_code == 200:
                content = response.text

                if only_params:
                    # Extract only parameters
                    all_params = extract_parameters(content)
                    
                    for param in all_params:
                        if not is_in_array(param, Parameters):
                            Parameters.append(param)
                            if activation_flag:
                                print(Fore.CYAN + f"URL: {js_url} - Extracted Parameter: {param}" + Style.RESET_ALL)
                            else:
                                print(Fore.CYAN + f"Extracted Parameter: {param}" + Style.RESET_ALL)
                            my_output.write(f"{param}\n")
                            success_output.write(f"{js_url}/{param}\n")
                else:
                    # Extract URLs and endpoints (original functionality)
                    all_urls = extract_all_urls(content)

                    for url in all_urls:
                        if activation_flag:
                            print(Fore.GREEN + f"URL: {js_url} - Extracted URL: {url}" + Style.RESET_ALL)
                        else:
                            print(Fore.GREEN + f"Extracted URL: {url}" + Style.RESET_ALL)
                        my_output.write(f"{url}\n")
                        success_output.write(f"{js_url}/{url}\n")

            else:
                print(Fore.RED + f"[ - ] Bad JS File Detected - URL: {js_url}" + Style.RESET_ALL)
    except Exception as e:
        print(Fore.RED + f"[ - ] Error accessing {js_url}: {e}" + Style.RESET_ALL)

def main():
    parser = argparse.ArgumentParser(description='EndpointsExtractor Tool')
    parser.add_argument('-u', dest='single_url', help='Single URL to grep endpoints from')
    parser.add_argument('-l', dest='urls_list', help='List of .js file URLs to grep endpoints from')
    parser.add_argument('-o', dest='output', default='js_endpoints.txt', help='Output file')
    parser.add_argument('-p', dest='activation_flag', action='store_true', help='Public mode for showing the URLs of each endpoint & showing the function (endpoints/fetch)')
    parser.add_argument('-t', dest='threads', type=int, default=1, help='Number of threads to use for concurrent processing')
    parser.add_argument('--only-params', dest='only_params', action='store_true', help='Extract only parameters and save to params.txt')

    args = parser.parse_args()

    if not args.single_url and not args.urls_list or args.single_url and args.urls_list:
        parser.error('Please use either -u for single_url mode or -l for URLs_list mode, not both or neither')

    if args.single_url:
        gimme_js_link(args.single_url, args.output, args.activation_flag, args.only_params)
    elif args.urls_list:
        with open(args.urls_list, 'r') as urls_file:
            with ThreadPoolExecutor(max_workers=args.threads) as executor:
                executor.map(lambda line: gimme_js_link(line.strip(), args.output, args.activation_flag, args.only_params), urls_file)

if __name__ == "__main__":
    main()
