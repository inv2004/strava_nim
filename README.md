### Automatic training diary from strava

The draft version is able to:
- [x] Starts http server to redirect into google and strava auth's
- [x] Request google email and spreadsheet access
- [x] Requests strava activities access
- [x] Stores tokens locally
- [x] Refresh token after expiration
- [x] Find current date plan from spreadsheet
- [x] Download watts stream from strava
- [x] Find best intervals for the mentioned plan
- [x] Store result into spreadsheet
- [x] Process for all stored users

### Build
```shell
nimble -d:ssl -d:release build
```

### First run
```shell
> .\strava_nim.exe --reg
[01:54:03] - INFO: Browser to the http://localhost:8090 for registration
```

testdb.db contains jsons with tokens

### Normal run
```shell
> .\strave_nim.exe
```

