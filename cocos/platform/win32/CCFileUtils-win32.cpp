/****************************************************************************
Copyright (c) 2010-2012 cocos2d-x.org
Copyright (c) 2013-2014 Chukong Technologies Inc.

http://www.cocos2d-x.org

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
****************************************************************************/

#include "platform/CCPlatformConfig.h"
#if CC_TARGET_PLATFORM == CC_PLATFORM_WIN32

#include "CCFileUtils-win32.h"
#include "CCUtils-win32.h"
#include "platform/CCCommon.h"
#include <Shlobj.h>
#include <regex>

using namespace std;

NS_CC_BEGIN

#define CC_MAX_PATH  512

// The root path of resources, the character encoding is UTF-8.
// UTF-8 is the only encoding supported by cocos2d-x API.
static std::string s_resourcePath = "";

// D:\aaa\bbb\ccc\ddd\abc.txt --> D:/aaa/bbb/ccc/ddd/abc.txt
static inline std::string convertPathFormatToUnixStyle(const std::string& path)
{
    std::string ret = path;
    int len = ret.length();
    for (int i = 0; i < len; ++i)
    {
        if (ret[i] == '\\')
        {
            ret[i] = '/';
        }
    }
    return ret;
}

// D:/aaa/bbb/ccc/ddd/abc.txt --> D:\aaa\bbb\ccc\ddd\abc.txt
static inline std::string convertPathFormatToWindowStyle(const std::string& path)
{
    std::string ret = path;
    int len = ret.length();
    for (int i = 0; i < len; ++i)
    {
        if (ret[i] == '/')
        {
            ret[i] = '\\';
        }
    }
    return ret;
}

static void _checkPath()
{
    if (s_resourcePath.empty())
    {
        WCHAR utf16Path[CC_MAX_PATH] = { 0 };
        GetModuleFileNameW(NULL, utf16Path, CC_MAX_PATH - 1);
        WCHAR *pUtf16ExePath = &(utf16Path[0]);

        // We need only directory part without exe
        WCHAR *pUtf16DirEnd = wcsrchr(pUtf16ExePath, L'\\');

        char utf8ExeDir[CC_MAX_PATH] = { 0 };
        int nNum = WideCharToMultiByte(CP_UTF8, 0, pUtf16ExePath, pUtf16DirEnd - pUtf16ExePath + 1, utf8ExeDir, sizeof(utf8ExeDir), nullptr, nullptr);

        s_resourcePath = convertPathFormatToUnixStyle(utf8ExeDir);
    }
}

FileUtils* FileUtils::getInstance()
{
    if (s_sharedFileUtils == nullptr)
    {
        s_sharedFileUtils = new FileUtilsWin32();
        if(!s_sharedFileUtils->init())
        {
          delete s_sharedFileUtils;
          s_sharedFileUtils = nullptr;
          CCLOG("ERROR: Could not init CCFileUtilsWin32");
        }
    }
    return s_sharedFileUtils;
}

FileUtilsWin32::FileUtilsWin32()
{
}

bool FileUtilsWin32::init()
{
    _checkPath();
    _defaultResRootPath = s_resourcePath;
    return FileUtils::init();
}

bool FileUtilsWin32::isFileExistInternal(const std::string& strFilePath) const
{
    if (0 == strFilePath.length())
    {
        return false;
    }

    std::string strPath = strFilePath;
    if (!isAbsolutePath(strPath))
    { // Not absolute path, add the default root path at the beginning.
        strPath.insert(0, _defaultResRootPath);
    }

    WCHAR utf16Buf[CC_MAX_PATH] = {0};
    MultiByteToWideChar(CP_UTF8, 0, strPath.c_str(), -1, utf16Buf, sizeof(utf16Buf)/sizeof(utf16Buf[0]));

    DWORD attr = GetFileAttributesW(utf16Buf);
    if (attr == INVALID_FILE_ATTRIBUTES || (attr & FILE_ATTRIBUTE_DIRECTORY))
    {
        return false;   //  not a file
    }
    else
    {
        WIN32_FIND_DATAA ffd;
        HANDLE hFind = FindFirstFileA(strPath.c_str(), &ffd);
        std::string filename(ffd.cFileName);
        size_t pos = strFilePath.find(filename);
        if (pos + filename.length() != strFilePath.length())
        {
            std::string realFile = strPath.substr(0, strPath.length() - filename.length()) + filename;
            CCLOG("WARNING: File case-sensitive.\n%s\n%s\n\n", strPath.c_str(), realFile.c_str());
        }
    }
    return true;
}

bool FileUtilsWin32::isAbsolutePath(const std::string& strPath) const
{
    //CCLOG("FileUtilsWin32::isAbsolutePath path = %s", strPath.c_str());
    if (   (strPath.length() > 2
        && ( (strPath[0] >= 'a' && strPath[0] <= 'z') || (strPath[0] >= 'A' && strPath[0] <= 'Z') )
        && strPath[1] == ':') || (strPath[0] == '/' && strPath[1] == '/'))
    {
        return true;
    }
    return false;
}

Data FileUtilsWin32::getData(const std::string& filename, bool forString)
{
    if (filename.empty())
    {
        return Data::Null;
    }

    unsigned char *buffer = nullptr;

    size_t size = 0;
    do
    {
        // read the file from hardware
        std::string fullPath = FileUtils::getInstance()->fullPathForFilename(filename);

        WCHAR wszBuf[CC_MAX_PATH] = {0};
        MultiByteToWideChar(CP_UTF8, 0, fullPath.c_str(), -1, wszBuf, sizeof(wszBuf)/sizeof(wszBuf[0]));

        HANDLE fileHandle = ::CreateFileW(wszBuf, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, NULL, nullptr);
        CC_BREAK_IF(fileHandle == INVALID_HANDLE_VALUE);

        size = ::GetFileSize(fileHandle, nullptr);

        if (forString)
        {
            buffer = (unsigned char*) malloc(size + 1);
            buffer[size] = '\0';
        }
        else
        {
            buffer = (unsigned char*) malloc(size);
        }
        DWORD sizeRead = 0;
        BOOL successed = FALSE;
        successed = ::ReadFile(fileHandle, buffer, size, &sizeRead, nullptr);
        ::CloseHandle(fileHandle);

        if (!successed)
        {
            free(buffer);
            buffer = nullptr;
        }
    } while (0);

    Data ret;

    if (buffer == nullptr || size == 0)
    {
        std::string msg = "Get data from file(";
        // Gets error code.
        DWORD errorCode = ::GetLastError();
        char errorCodeBuffer[20] = {0};
        snprintf(errorCodeBuffer, sizeof(errorCodeBuffer), "%d", errorCode);

        msg = msg + filename + ") failed, error code is " + errorCodeBuffer;
        CCLOG("%s", msg.c_str());
    }
    else
    {
        ret.fastSet(buffer, size);
    }
    return ret;
}

std::string FileUtilsWin32::getSuitableFOpen(const std::string& filenameUtf8) const
{
    //return convertPathFormatToWindowStyle(UTF8StringToMultiByte(filenameUtf8));
    return UTF8StringToMultiByte(filenameUtf8);
}

unsigned char* FileUtilsWin32::getFileData(const std::string& filename, const char* mode, ssize_t* size)
{
    unsigned char * pBuffer = nullptr;
    *size = 0;
    do
    {
        // read the file from hardware
        std::string fullPath = fullPathForFilename(filename);

        WCHAR wszBuf[CC_MAX_PATH] = {0};
        MultiByteToWideChar(CP_UTF8, 0, fullPath.c_str(), -1, wszBuf, sizeof(wszBuf)/sizeof(wszBuf[0]));

        HANDLE fileHandle = ::CreateFileW(wszBuf, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, NULL, nullptr);
        CC_BREAK_IF(fileHandle == INVALID_HANDLE_VALUE);

        *size = ::GetFileSize(fileHandle, nullptr);

        pBuffer = (unsigned char*) malloc(*size);
        DWORD sizeRead = 0;
        BOOL successed = FALSE;
        successed = ::ReadFile(fileHandle, pBuffer, *size, &sizeRead, nullptr);
        ::CloseHandle(fileHandle);

        if (!successed)
        {
            free(pBuffer);
            pBuffer = nullptr;
        }
    } while (0);

    if (! pBuffer)
    {
        std::string msg = "Get data from file(";
        // Gets error code.
        DWORD errorCode = ::GetLastError();
        char errorCodeBuffer[20] = {0};
        snprintf(errorCodeBuffer, sizeof(errorCodeBuffer), "%d", errorCode);

        msg = msg + filename + ") failed, error code is " + errorCodeBuffer;
        CCLOG("%s", msg.c_str());
    }
    return pBuffer;
}

std::string FileUtilsWin32::getPathForFilename(const std::string& filename, const std::string& resolutionDirectory, const std::string& searchPath) const
{
    std::string unixFileName = convertPathFormatToUnixStyle(filename);
    std::string unixResolutionDirectory = convertPathFormatToUnixStyle(resolutionDirectory);
    std::string unixSearchPath = convertPathFormatToUnixStyle(searchPath);

    return FileUtils::getPathForFilename(unixFileName, unixResolutionDirectory, unixSearchPath);
}

std::string FileUtilsWin32::getFullPathForDirectoryAndFilename(const std::string& strDirectory, const std::string& strFilename) const
{
    std::string unixDirectory = convertPathFormatToUnixStyle(strDirectory);
    std::string unixFilename = convertPathFormatToUnixStyle(strFilename);

    return FileUtils::getFullPathForDirectoryAndFilename(unixDirectory, unixFilename);
}

string FileUtilsWin32::getWritablePath() const
{
    if (_writablePath.length())
    {
        return _writablePath;
    }

    // Get full path of executable, e.g. c:\Program Files (x86)\My Game Folder\MyGame.exe
    char full_path[CC_MAX_PATH + 1];
    ::GetModuleFileNameA(nullptr, full_path, CC_MAX_PATH + 1);

    // Debug app uses executable directory; Non-debug app uses local app data directory
//#ifndef _DEBUG
        // Get filename of executable only, e.g. MyGame.exe
        char *base_name = strrchr(full_path, '\\');

        if(base_name)
        {
            char app_data_path[CC_MAX_PATH + 1];

            // Get local app data directory, e.g. C:\Documents and Settings\username\Local Settings\Application Data
            if (SUCCEEDED(SHGetFolderPathA(nullptr, CSIDL_LOCAL_APPDATA, nullptr, SHGFP_TYPE_CURRENT, app_data_path)))
            {
                string ret((char*)app_data_path);

                // Adding executable filename, e.g. C:\Documents and Settings\username\Local Settings\Application Data\MyGame.exe
                ret += base_name;

                // Remove ".exe" extension, e.g. C:\Documents and Settings\username\Local Settings\Application Data\MyGame
                ret = ret.substr(0, ret.rfind("."));

                ret += "\\";

                // Create directory
                if (SUCCEEDED(SHCreateDirectoryExA(nullptr, ret.c_str(), nullptr)))
                {
                    return convertPathFormatToUnixStyle(ret);
                }
            }
        }
//#endif // not defined _DEBUG

    // If fetching of local app data directory fails, use the executable one
    string ret((char*)full_path);

    // remove xxx.exe
    ret =  ret.substr(0, ret.rfind("\\") + 1);

    ret = convertPathFormatToUnixStyle(ret);

    return ret;
}

bool FileUtilsWin32::renameFile(const std::string &oldfullpath, const std::string& newfullpath)
{
    CCASSERT(!oldfullpath.empty(), "Invalid path");
    CCASSERT(!newfullpath.empty(), "Invalid path");

    std::wstring _wNew = StringUtf8ToWideChar(newfullpath);
    std::wstring _wOld = StringUtf8ToWideChar(oldfullpath);

    if (FileUtils::getInstance()->isFileExist(newfullpath))
    {
        if (!DeleteFile(_wNew.c_str()))
        {
            CCLOGERROR("Fail to delete file %s !Error code is 0x%x", newfullpath.c_str(), GetLastError());
        }
    }

    if (MoveFile(_wOld.c_str(), _wNew.c_str()))
    {
        return true;
    }
    else
    {
        CCLOGERROR("Fail to rename file %s to %s !Error code is 0x%x", oldfullpath.c_str(), newfullpath.c_str(), GetLastError());
        return false;
    }
}

bool FileUtilsWin32::renameFile(const std::string &path, const std::string &oldname, const std::string &name)
{
    CCASSERT(!path.empty(), "Invalid path");
    std::string oldPath = path + oldname;
    std::string newPath = path + name;

    std::regex pat("\\/");
    std::string _old = std::regex_replace(oldPath, pat, "\\");
    std::string _new = std::regex_replace(newPath, pat, "\\");

    return renameFile(_old, _new);
}

bool FileUtilsWin32::createDirectory(const std::string& path)
{
    CCASSERT(!path.empty(), "Invalid path");

    if (isDirectoryExist(path))
        return true;

    // Split the path
    size_t start = 0;
    size_t found = path.find_first_of("/\\", start);
    std::string subpath;
    std::vector<std::string> dirs;

    if (found != std::string::npos)
    {
        while (true)
        {
            subpath = path.substr(start, found - start + 1);
            if (!subpath.empty())
                dirs.push_back(subpath);
            start = found + 1;
            found = path.find_first_of("/\\", start);
            if (found == std::string::npos)
            {
                if (start < path.length())
                {
                    dirs.push_back(path.substr(start));
                }
                break;
            }
        }
    }


    if ((GetFileAttributesA(path.c_str())) == INVALID_FILE_ATTRIBUTES)
    {
        subpath = "";
        for (int i = 0; i < dirs.size(); ++i)
        {
            subpath += dirs[i];
            if (!isDirectoryExist(subpath))
            {
                BOOL ret = CreateDirectoryA(subpath.c_str(), NULL);
                if (!ret && ERROR_ALREADY_EXISTS != GetLastError())
                {
                    return false;
                }
            }
        }
    }
    return true;
}

bool FileUtilsWin32::removeDirectory(const std::string& path)
{
    if (path.size() > 0 && path[path.size() - 1] != '/')
    {
        CCLOGERROR("Fail to remove directory, path must termniate with '/': %s", path.c_str());
        return false;
    }

    // Remove downloaded files
    std::string command = "cmd /c rd /s /q ";
    // Path may include space.
    command += "\"" + path + "\"";

    if (WinExec(command.c_str(), SW_HIDE) > 31)
        return true;
    else
        return false;
}

NS_CC_END

#endif // CC_TARGET_PLATFORM == CC_PLATFORM_WIN32

