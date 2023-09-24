cls
del OGL.exe
del OGL.obj
del OGL.res

rc.exe OGL.rc
REM link.exe OGL.obj OGL.res /LIBPATH:C:\glew\lib\Release\x64 user32.lib gdi32.lib /SUBSYSTEM:WINDOWS
nvcc.exe -o OGL.exe -I "C:\glew\include" -I "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v11.6\include" -L "C:\glew\lib\Release\x64" -L "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v11.6\lib\x64" user32.lib gdi32.lib OGL.cu postProcessGL.cu
OGL.exe