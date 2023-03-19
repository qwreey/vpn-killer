local spawn = require "coro-spawn"
local timer = require "timer"
local path = require "path"
local filesystem = require "fs"

-- 일반적 아이피
local normalIP = args[1] -- 명령행 인자에서 가져옴
-- 즉 프로그램 실행 때
-- > vpnkiller 115.111.111.111
-- 이렇게 아이피를 넣어주면 됨

-- 경고 텍스트 파일이 담길 위치
local textFile = path.resolve( -- 경로 리솔브
    path.join( -- 경로 합치기
        process.env.USERPROFILE, -- 유저 폴더에
        "vpnChecker.txt" -- vpnChecker.txt 라는 파일
    )
)
-- 경고 텍스트 파일에 담길 글
local content = [[
 * IP 변경이 감지되었습니다 
이 PC 에서 VPN 을 사용한 것이 확인되었습니다.
PC 를 1 분 뒤 종료합니다.
]]

-- 메모장 여러개 열림 방지로, 셧다운 진행중인지 확인하는 값
local shutdowned = false

-- 아이피 가져오는 함수
-- 리턴 : 아이피, 연결됨(인터넷 있으면 true)
local function getIP()
    -- nslookup myip.opendns.com. resolver1.opendns.com
    -- 위 명령을 cmd 에서 실행함
    local process = spawn("nslookup",{args = {"myip.opendns.com.","resolver1.opendns.com"},stdio = {nil,true,true},hide = true})
    if not process then error("process spawn failed") end

    -- 출력을 가져옴
    local output = {} -- 명령어 결과를 넣을곳
    for str in process.stdout.read do -- 를 표준 출력에서 끌어다가 str output 에 넣음
        table.insert(output,str)
    end
    process.waitExit() -- 프로그램이 끝나기를 기다림
    output = table.concat(output) -- 받은 모든 출력을 한 문자열로 합침

    -- 문자열 매칭을 통해서 ip 부분을 따옴
    local ip = output:match":[ \t]*myip%.opendns%.com[\n\r]*Address:[ \t]*([%d%.]+)"
    local connection = true
    if output:match":[ \t]*Un[kK]nown" then
        connection = false
    end

    return ip,connection
end

-- 셧다운시 실행될 함수
local function shutdown()
    -- 경고 텍스트 파일을 씀
    filesystem.writeFileSync(
        textFile, -- 파일 위치
        content -- 파일 내용
    )
    spawn("notepad.exe",{ -- 메모장을 염
        args = {textFile}, -- 경고 텍스트 파일 위치
        detached = true, -- 분리된 프로세스로 실행
        stdio = {nil,nil,nil} -- 입출력 제거
    })
    timer.setTimeout(
        60*1000, -- 딜레이 주기
        function () -- 딜레이 후 실행할 코드
            spawn("shutdown",{ -- 윈도우 셧다운 명령
                args = { -- 명령행 인자
                    "/f", -- 사용자에게 미리 경고하지 않고 실행 중인 응용 프로그램을 강제로 닫습니다.
                    "/p"  -- 시간 제한 또는 경고 없이 로컬 컴퓨터를 끕니다.
                }
            })
        end
    )
end

-- ip 변경 감지하는 함수
local function onIPChecked(ip)
    -- 아이피 검증, 확인해보니 VPN 사용중에는 ip 값을 얻을 수 없어
    -- nil (비어있는값) 이 나오던데 어쨋든 정상 경우와 비정상 경우 채킹에는 상관없음
    if ( (not ip) or (not normalIP:find(ip,1,true)) ) and (not shutdowned) then
        shutdowned = true -- 여러번 셧다운 됨을 방지
        shutdown() -- 셧다운
    end
end

-- 인풋 가져오는 함수
local function readInput() -- 알 필요 없는 끔찍한 기믹으로 구성됨 (루틴 비활성화후 libuv 에서 none block 으로 stdin 을 읽어오고 다시 루틴을 활성화)
    local routine = coroutine.running()
    require"pretty-print".stdin:read_start(coroutine.wrap(function (err, data)
        require"pretty-print".stdin:read_stop()
        coroutine.resume(routine,data)
    end))
    return coroutine.yield()
end

-- 관리자로 프로그램이 실행중인지 확인하는 함수
local function checkPermission()
    return filesystem.existsSync(path.resolve(path.join(process.env.SYSTEMROOT,"SYSTEM32/WDI/LOGFILES")))
end

-- 설치 함수
local function install(ips) -- 여러 아이피 (여러 와이파이 지원을 위해) 를 넣을 수 있는 ips 값
    local ip,hasConnection = getIP()

    -- 인터넷 연결이 없어?!
    if (not hasConnection) and (not ips) then
        print("인터넷 연결이 없습니다. 기본 아이피를 불러오는데 실패하였습니다.")
        return
    end

    -- 여러 아이피 호환
    if ips then -- 확인된 인터넷 + 입력된 아이피
        if ip then
            ip = table.concat{ip,",",ips}
        else
            ip = ips
        end
    end
    if (not ip) or ip == "" or ip:match("^[ \n\t\r]+$") then
        print("입력된 아이피가 없습니다.")
        return
    end

    -- 대충 이 프로그램을 시작 프로그램으로 등록해줌
    local this = path.resolve(args[0])
    local command = table.concat{'"',this,'" ',ip}
    print("이미 등록된 설치 확인중 . . .\n------------ 명령기록 -------------")
    spawn("schtasks",{ -- 이미 있던 스캐줄 제거
        args = {
            "/delete",
            "/f",
            "/tn","VPNCHECKER"
        },
        stdio = {0,1,2}
    }).waitExit()
    local errorCode = spawn("schtasks",{ -- 스캐줄 등록
        args = {
            "/create",
            "/tn","VPNCHECKER", -- 스캐줄 이름 지정
            "/tr", command,
            "/sc","onlogon" -- 로그인시 사용되도록 지정
        },
        stdio = {0,1,2}
    }).waitExit()
    -- 오류 발생시
    if errorCode ~= 0 then
        print("오류가 발생했습니다. 설치 명령은 관리자 권한을 필요로 하므로\n관리자 권한으로 cmd 를 실행하였는지 확인해주세요")
    else
        print(("-----------------------------------\n\n명령 %s 가 등록되었습니다."):format(command))
        print(("%s 파일을 옮기면 설치를 다시 해야 합니다.\n만약 옮긴 경우 다시 설치를 진행하세요\n설치가 완료되었습니다. 재시작시 변경 사항이 적용됩니다"):format(tostring(args[0])))
    end
end

local function uninstall()
    print("------------ 명령기록 -------------")
    local errorCode = spawn("schtasks",{ -- 이미 있던 스캐줄 제거
        args = {
            "/delete",
            "/f",
            "/tn","VPNCHECKER"
        },
        stdio = {0,1,2}
    }).waitExit()

    print("-----------------------------------\n")
    if errorCode ~= 0 then
        print("제거중 오류가 발생했습니다")
    else
        print("성공적으로 제거했습니다. 재시작시 변경 사항이 적용됩니다")
    end
end

-- 인자가 비어있으면 설치할것인지 물어봄
if (not normalIP) or normalIP == "" then
    if not checkPermission() then
        print("관리자 권한이 없습니다. 프로그램 우클릭 후 '관리자 권한으로 실행' 을 눌러주세요")
        readInput()
        return
    end

    print("프로그램에 아무런 옵션이 제공되지 않았습니다.")
    print("설치를 진행하시겠습니까? (관리자 권한 필요)")
    print("주의: 삭제 방지를 위해 이 프로그램 파일을 찾기 어려운곳에 두어야 합니다")
    print("      예시) C:\\Windows\\System32")
    print("      또한 프로그램 이름이 작업 관리자에 노출되므로")
    print("      유추하기 힘든 이름을 가져야 합니다. 프로그램 명을 변경해보세요")
    print("      예시) system.exe  Runtime Broker.exe")
    print("프로그램 삭제의 경우 uninstall 을 입력하세요")
    print("Ctrl+C : 취소    Enter : 진행    uninstall 입력후 Enter : 제거")
    local mode = readInput()

    if mode and mode:lower():match("uninstall") then
        print("제거를 진행합니다 . . .")
        uninstall()
    else
        print(" * 허용할 아이피를 입력해주세요")
        print("   학교에 와이파이가 여러대 있는 경우, 각각의 공인 아이피를")
        print("   확인한 뒤 , 으로 나누어 입력하세요.")
        print("   예: 111.111.111.111,222.222.222.222,333.333.333.333")
        print("   (현재 연결된 인터넷은 자동으로 입력되어 있습니다.")
        print("    이 인터넷만 허용하는 경우 엔터를 누르세요)")
        local ip = getIP()
        io.write(table.concat{"> ",(ip or ""),(ip and "," or "")})
        local ips = readInput()
        if ips == "" then ips = nil end
        print("")
        install(ips)
    end
    print("(엔터를 눌러 프로그램 종료 . . .)")
    readInput()
    return
end

-- 만약 첫째 인자가 install 이면 설치를 시도함
if normalIP == "install" then
    if not checkPermission() then
        print("관리자 권한이 없습니다.")
    end
    install(args[2])
    return
end

-- cmd 창을 숨기기 위해 나 자신을 다시 실행 (detached 상태로 hide 해서)
if args[2] ~= "running" then
    spawn(args[0],{
        args = {normalIP,"running"},
        hide = true,
        detached = true
    })
    os.exit()
end

-- 코루틴 (대충 병렬로 작업을 돌리는 무언가인데 알필요가 없을듯)
coroutine.wrap(function ()
    while true do -- 무한루프
        local ip,hasConnection = getIP() -- 아이피 가져옴
        if hasConnection then -- 만약 인터넷에 연결되어 있다면
            onIPChecked(ip) -- 받은 아이피를 채크 함수에 넣음
        end
        timer.sleep(5000) -- 이것을 5000ms (5초) 마다 반복하도록 만듬
    end
end)()
