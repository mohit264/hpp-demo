#include<stdio.h>
#include<stdlib.h>
#include<Windows.h>

#include <GL/glew.h> // THIS MUST BE ABOVE gl.h
#include<GL/gl.h>

#include<cuda_runtime.h>
#include<cuda_gl_interop.h>
// CUDA utilities and system includes


#include "OGL.h"
#include "Sphere.h"
#include "vmath.h"
using namespace vmath;

// OpenGL Libraries
#pragma comment(lib, "glew32.lib")
#pragma comment(lib, "OpenGL32.lib")
#pragma comment(lib,"Sphere.lib")
#pragma comment(lib, "cudart.lib")

#define WIN_WIDTH 800
#define WIN_HEIGHT 600
#define FBO_WIDTH 512
#define FBO_HEIGHT 512

// Global Function Declarations
LRESULT CALLBACK WndProc(HWND, UINT, WPARAM, LPARAM);

// Global Variable declarations
HWND ghwnd = NULL;
HDC ghdc = NULL;
HGLRC ghrc = NULL;

BOOL gbActiveWindow = FALSE;
BOOL gbFullScreen = FALSE;
FILE *gpFile = NULL;

// Programable pipeline related global variables
GLuint shaderProgramObj;
int winWidth;
int winHeight;


enum 
{
    MVD_ATTRIBUTE_POSITION = 0,
    MVD_ATTRIBUTE_COLOR,
    MVD_ATTRIBUTE_NORMAL,
    MVD_ATTRIBUTE_TEXTURE0
};

GLuint vao_cube;
GLuint vbo_cube_position;
GLuint vbo_cube_texcoord;
GLuint mvpMatrixUniform;
GLuint texture_checkerboard;
GLuint textureSamplerUniform;

mat4 perspectiveProjectionMatrix;

GLfloat angleCube = 0.0f;

// FBO Related variables
GLuint fbo;
GLuint rbo;
GLuint fbo_texture;
bool bfboResult = false;

GLuint vbo_gpu;
cudaError_t cudaResult;
struct cudaGraphicsResource *graphicResource = NULL;
BOOL onGPU = FALSE;

unsigned int size_tex_data;
unsigned int num_texels;
unsigned int num_values;

// for proper depth test while rendering the scene
GLuint tex_screen;      // where we render the image
GLuint tex_cudaResult;  // where we will copy the CUDA result

float rotate[3];

char *ref_file = NULL;
bool enable_cuda = true;
bool animate = true;
int blur_radius = 3/2;
int max_blur_radius = 16;

unsigned int *cuda_dest_resource;
GLuint shDrawTex;  // draws a texture
struct cudaGraphicsResource *cuda_tex_result_resource;
extern cudaTextureObject_t inTexObject;
struct cudaGraphicsResource *cuda_tex_screen_resource;

extern "C" void launch_cudaProcess(dim3 grid, dim3 block, int sbytes,
                                   cudaArray *g_data, unsigned int *g_odata,
                                   int imgw, int imgh, int tilew, int radius,
                                   float threshold, float highlight);

//texture Scene global variables 

// Programable pipeline related global variables
GLuint shaderProgram_sphere;

GLuint vao_sphere;
GLuint vbo_position_sphere;
GLuint vbo_normal_sphere;
GLuint vbo_elements_sphere;

GLuint modelMatrixUniform__sphere;
GLuint viewMatrixUniform__sphere;
GLuint projectionMatrixUniform__sphere;

GLuint laUniform_sphere[3];
GLuint ldUniform_sphere[3];
GLuint lsUniform_sphere[3];
GLuint lightPositionUniform_sphere[3];

GLuint kaUniform_sphere;
GLuint kdUniform_sphere;
GLuint ksUniform_sphere;
GLuint materiaShininessUniform_sphere;

GLuint lightingEnabledUniform_sphere;

BOOL bLight = FALSE;

float sphere_vertices[1146];
float sphere_normals[1146];
float sphere_textures[764];
unsigned short sphere_elements[2280];

unsigned int numVertices_sphere;
unsigned int numElements_sphere;

struct Light
{
    vec4 lightAmbient;
    vec4 lightDiffused;
    vec4 lightSpecular;
    vec4 lightPosition;
};

Light lights[3]; // Two different lights

mat4 perspectiveProjectionMatrix_sphere;

GLfloat materialAmbient_sphere[] = {0.0f, 0.0f, 0.0f, 0.0f};
GLfloat materialDiffused_sphere[] = {1.0f, 1.0f, 1.0f, 1.0f};
GLfloat materialSpecular_sphere[] = {1.0f, 1.0f, 1.0f, 1.0f};
GLfloat materialShininess_sphere = 128.0f;

GLfloat lightAngleZero_sphere = 0.0f;
GLfloat lightAngleOne_sphere = 0.0f;
GLfloat lightAngleTwo_sphere = 0.0f;
bool enable_cuda_postProcess = false;

int kernel[9];


GLubyte cpuConvolutionArray[FBO_WIDTH][FBO_HEIGHT][4];


GLfloat remap(GLfloat x, GLfloat in_min, GLfloat in_max, GLfloat out_min, GLfloat out_max) {
	return (x - in_min) * (out_max - out_min) / (in_max - in_min) + out_min;
}

float clampToCPUFloat(float x, float a, float b) { return max(a, min(b, x)); }

int clampToCPUInt(int x, int a, int b) { return max(a, min(b, x)); }

int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpszCmdLine, int iCmdShow)
{
    // Function Declarations
    int initialize(void);
    void display(void);
    void update(void);
    void uninitialize(void);

    // Varible Declarations
    HWND hwnd;
    MSG msg;
    TCHAR szAppName[] = TEXT("My Window");
    WNDCLASSEX wndClass;
    BOOL bDone = FALSE;
    int iRetVal = 0;

    int iScreenX = GetSystemMetrics(SM_CXSCREEN);
    int iScreenY =  GetSystemMetrics(SM_CYSCREEN);
    
    //code
    if (fopen_s(&gpFile, "Log.txt", "w") != 0)
    {
        MessageBox(NULL, TEXT("Log File Creation Failed... Exiting Now!!!"), TEXT("I/O Error"), MB_OK);
        exit(0);
    }
    else
    {
        fprintf(gpFile, "Log File is Created Succesfully\n");
    }

    wndClass.cbSize = sizeof(WNDCLASSEX);
    wndClass.cbClsExtra = 0;
    wndClass.cbWndExtra = 0;
    wndClass.hInstance = hInstance;
    wndClass.lpfnWndProc = WndProc;
    wndClass.lpszMenuName = NULL;
    wndClass.lpszClassName = szAppName;
    wndClass.hbrBackground = (HBRUSH) GetStockObject(BLACK_BRUSH);
    wndClass.hIcon = LoadIcon(hInstance, MAKEINTRESOURCE(MYICON));
    wndClass.hCursor = LoadCursor(NULL, IDC_ARROW);
    wndClass.style = CS_HREDRAW | CS_VREDRAW | CS_OWNDC;
    wndClass.hIconSm = LoadIcon(hInstance, MAKEINTRESOURCE(MYICON));
    
    // Register Window
    RegisterClassEx(&wndClass);

    hwnd =  CreateWindowEx(WS_EX_APPWINDOW,
        szAppName, 
        TEXT("MVD : OGL Window!"), 
        WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN | WS_CLIPSIBLINGS | WS_VISIBLE, 
        (iScreenX/2) - (WIN_WIDTH/2),
        (iScreenY/2) - (WIN_HEIGHT/2),
        WIN_WIDTH,
        WIN_HEIGHT,
        NULL,
        NULL,
        hInstance,
        NULL);

    ghwnd = hwnd;

    // Initialize
    iRetVal = initialize();

    if (iRetVal == -1)
    {
        fprintf(gpFile, "Choose Pixel Format Failed!\n");
        uninitialize();
    }
    else if (iRetVal == -2)
    {
        fprintf(gpFile, "Set Pixel Format Failed!\n");
        uninitialize();
    }
    else if (iRetVal == -3)
    {
        fprintf(gpFile, "Create OpenGL Context Failed!\n");
        uninitialize();
    }
    else if (iRetVal == -4)
    {
        fprintf(gpFile, "Making OpenGL Context as Current Context Failed!\n");
        uninitialize();
    }
    else if (iRetVal == -5)
    {
        fprintf(gpFile, "Glew Init() Failed!\n");
        uninitialize();
    }
    else if (iRetVal == -6)
    {
        fprintf(gpFile, "Texture Loading Failed!\n");
        uninitialize();
    }

    ShowWindow(hwnd, iCmdShow);

    // Forgrounding and Focusing the window
    SetForegroundWindow(hwnd); // Both ghwnd and hwnd will work here, but since hwnd is local here that's why we're using the same
    SetFocus(hwnd);

    while (bDone == FALSE)
    {
        if (PeekMessage(&msg, NULL, 0, 0, PM_REMOVE))
        {
            if (msg.message == WM_QUIT)
            {
                bDone = TRUE;
            }
            else
            {
                TranslateMessage(&msg);
                DispatchMessage(&msg);
            }
        }
        else
        {
            if (gbActiveWindow)
            {
                // Render the scene
                display();

                // Update the scene
                update();
            }
        }
    }

    // Janmejay and Takshak. Indray Swah, Takshkay swah
    uninitialize();
    return ((int) msg.wParam);
}

LRESULT CALLBACK WndProc(HWND hwnd, UINT iMsg, WPARAM wParam, LPARAM lParam)
{
    // Function Declarations
    void ToggleFullScreen(void);
    void resize(int, int);

    // Code
    
    switch (iMsg)
    {
        case WM_CHAR:
            switch (wParam)
            {
                case 'F':
                case 'f':
                    ToggleFullScreen();
                break;
                case 'L':
                case 'l':
                    if (bLight == FALSE)
                    {
                        bLight = TRUE;
                    }
                    else
                    {
                        bLight = FALSE;
                    }
                break;
                case '+':
                if (blur_radius < 16) {
                    blur_radius++;
                }
                break;
                case '-':
                if (blur_radius > 1) {
                    blur_radius--;
                }                
                break;
                case ' ':
                    enable_cuda_postProcess = !enable_cuda_postProcess;
                break;
                default:
                break;
            }
        break;
        case WM_KEYDOWN:
            switch (wParam)
            {
                case 27:
                    DestroyWindow(hwnd);
                break;
            
                default:
                break;
            }
        break;
        case WM_SETFOCUS:
            gbActiveWindow = TRUE;
        break;
        case WM_KILLFOCUS:
            gbActiveWindow = FALSE;
        break;
        case WM_ERASEBKGND:
            fprintf(gpFile, "ERASE BKGND is Called. \n");
            return 0;
        case WM_SIZE:
            // Every message has it's own unique information which is passed using LPARAM 
            // Here LOWORD : Width of the Window, HIWORD: Height of the Window
            resize(LOWORD(lParam), HIWORD(lParam));
        break;
        case WM_CLOSE:
            DestroyWindow(hwnd);
        break;
        case WM_DESTROY:
            PostQuitMessage(0);
        break;
    
        default:
        break;
    }
    return (DefWindowProc(hwnd, iMsg, wParam, lParam));
}

void ToggleFullScreen(void)
{
    // Variable Declarations
    static DWORD dwStyle;
    static WINDOWPLACEMENT wp;
    MONITORINFO mi;

    // Code
    fprintf(gpFile, "Entering ToggleFullScreen().\n");
    wp.length = sizeof(WINDOWPLACEMENT);

    if (gbFullScreen == FALSE)
    {
        dwStyle = GetWindowLong(ghwnd, GWL_STYLE);
        if (dwStyle & WS_OVERLAPPEDWINDOW)
        {
            mi.cbSize = sizeof(MONITORINFO);
            if (GetWindowPlacement(ghwnd, &wp) && 
                GetMonitorInfo(MonitorFromWindow(ghwnd, MONITORINFOF_PRIMARY), &mi))
            {
                SetWindowLong(ghwnd, GWL_STYLE, dwStyle & ~WS_OVERLAPPEDWINDOW);
                SetWindowPos(ghwnd, 
                    HWND_TOP, 
                    mi.rcMonitor.left, 
                    mi. rcMonitor.top, 
                    mi.rcMonitor.right - mi.rcMonitor.left, 
                    mi.rcMonitor.bottom - mi.rcMonitor.top, SWP_NOZORDER | SWP_FRAMECHANGED);
            }
        }
        ShowCursor(FALSE);
        gbFullScreen = TRUE;
    }
    else
    {
        SetWindowLong(ghwnd, GWL_STYLE, dwStyle | WS_OVERLAPPEDWINDOW);
        SetWindowPlacement(ghwnd, &wp);
        SetWindowPos(ghwnd, HWND_TOP, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOOWNERZORDER | SWP_NOZORDER | SWP_NOSIZE | SWP_FRAMECHANGED);
        ShowCursor(TRUE);
        gbFullScreen = FALSE;
    }
}

////////////////////////////////////////////////////////////////////////////////
void createTextureDst(GLuint *tex_cudaResult, unsigned int size_x,
                      unsigned int size_y) {
  // create a texture
  glGenTextures(1, tex_cudaResult);
  glBindTexture(GL_TEXTURE_2D, *tex_cudaResult);

  // set basic parameters
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);


  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, size_x, size_y, 0,
               GL_RGB, GL_UNSIGNED_BYTE, NULL);
  // register this texture with CUDA
  cudaGraphicsGLRegisterImage(
      &cuda_tex_result_resource, *tex_cudaResult, GL_TEXTURE_2D,
      cudaGraphicsMapFlagsWriteDiscard);
}



// copy image and process using CUDA
void processImage()
{
    void process(int, int, int);

  // run the Cuda kernel
  process(FBO_WIDTH, FBO_HEIGHT, blur_radius);

// CUDA generated data in cuda memory or in a mapped PBO made of BGRA 8 bits
// 2 solutions, here :
// - use glTexSubImage2D(), there is the potential to loose performance in
// possible hidden conversion
// - map the texture and blit the result thanks to CUDA API

  // We want to copy cuda_dest_resource data to the texture
  // map buffer objects to get CUDA device pointers
  cudaArray *texture_ptr;
  cudaGraphicsMapResources(1, &cuda_tex_result_resource, 0);
  cudaGraphicsSubResourceGetMappedArray(
      &texture_ptr, cuda_tex_result_resource, 0, 0);

  int num_texels = FBO_WIDTH * FBO_HEIGHT;
  int num_values = num_texels * 4;
  int size_tex_data = sizeof(GLubyte) * num_values;
  cudaMemcpyToArray(texture_ptr, 0, 0, cuda_dest_resource,
                                    size_tex_data, cudaMemcpyDeviceToDevice);

  cudaGraphicsUnmapResources(1, &cuda_tex_result_resource, 0);
}

////////////////////////////////////////////////////////////////////////////////
//! Run the Cuda part of the computation
////////////////////////////////////////////////////////////////////////////////
void process(int width, int height, int radius) {
  cudaArray *in_array;
  unsigned int *out_data;
  out_data = cuda_dest_resource;

  // map buffer objects to get CUDA device pointers
  cudaGraphicsMapResources(1, &cuda_tex_screen_resource, 0);
  // printf("Mapping tex_in\n");
  cudaGraphicsSubResourceGetMappedArray(
      &in_array, cuda_tex_screen_resource, 0, 0);

  // calculate grid size
  dim3 block(16, 16, 1);
  // dim3 block(16, 16, 1);
  dim3 grid(width / block.x, height / block.y, 1);
  int sbytes = (block.x + (2 * radius)) * (block.y + (2 * radius)) *
               sizeof(unsigned int);

  // execute CUDA kernel
  launch_cudaProcess(grid, block, sbytes, in_array, out_data, width, height,
                     block.x + (2 * radius), radius, 0.8f, 4.0f);

  cudaGraphicsUnmapResources(1, &cuda_tex_screen_resource, 0);
  cudaDestroyTextureObject(inTexObject);
}

void initCUDABuffers(int imgWidth, int imgHeight)
{
  // set up vertex data parameter
  num_texels = imgWidth * imgHeight;
  num_values = num_texels * 4;
  size_tex_data = sizeof(GLubyte) * num_values;
  cudaMalloc((void **)&cuda_dest_resource, size_tex_data);
}

int initialize(void)
{
    // Function declarations
    void resize(int, int);
    void printGLInfo(void);
    void uninitialize(void);
    bool createFBO(GLint, GLint);
    int initialize_sphere(int, int);
    void initCUDABuffers(int, int);
    void genCPUTexture(void);

    // Variable declarations
    PIXELFORMATDESCRIPTOR pfd;
    int iPixelFormatIndex = 0;

    // Code
    ZeroMemory(&pfd, sizeof(PIXELFORMATDESCRIPTOR));
 
    // Initialization of PIXELFORMATDESCRIPTOR
    pfd.nSize = sizeof(PIXELFORMATDESCRIPTOR);
    pfd.nVersion = 1;
    pfd.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER;
    pfd.iPixelType = PFD_TYPE_RGBA;
    pfd.cColorBits = 32;
    pfd.cRedBits = 8;
    pfd.cGreenBits = 8;
    pfd.cBlueBits = 8;
    pfd.cAlphaBits = 8;
    pfd.cDepthBits = 32;

    // Get DC
    ghdc = GetDC(ghwnd);

    // Choose Pixel Format
    iPixelFormatIndex = ChoosePixelFormat(ghdc, &pfd);

    // if above call is successfull then it returns positive value
    if (iPixelFormatIndex == 0)
    {
        return(-1);
    }
    
    // Set the chosen pixel format
    if (SetPixelFormat(ghdc, iPixelFormatIndex, &pfd) == FALSE)
    {
        return(-2) ;
    }
    
    // Create OpenGL rendering context
    // Divyatwacade Janare pahile pahul
    ghrc = wglCreateContext(ghdc);
        
    if (ghrc == NULL)
    {
        return(-3);
    }

    // Make Rendering Context as Current Context
    // This is bridging API as hdc is not aware of OpenGL
    if (wglMakeCurrent(ghdc, ghrc) == FALSE)
    {
        return(-4);
    }

    // glew initalization
    if (glewInit() != GLEW_OK)
    {
        return (-5);
    }
    
    // Print OpenGL Info
    printGLInfo();


    int dev_count = 0;
    // CUDA Init
    cudaResult = cudaGetDeviceCount(&dev_count);

    if (cudaResult != cudaSuccess)
    {
        fprintf(gpFile, "CUDA cudaGetDeviceCount() failed");
        uninitialize();
        exit(EXIT_FAILURE);
    }
    else if (dev_count == 0)
    {
        fprintf(gpFile, "No CUDA supported devices\n");
        uninitialize();
        exit(EXIT_FAILURE);
    }
        
    // Select CUDA supported Device
    cudaSetDevice(0); // Selecting the default 0th CUDA supported device

    // Vertex Shader
    const GLchar* vertexShaderSrcCode = 
        "#version 460 core" \
        "\n" \
        "in vec4 a_position;" \
        "in vec2 a_texcoord;" \
        "\n" \
        "uniform mat4 u_mvpMatrix;" \
        "out vec2 a_texcoord_out;" \
        "\n" \
        "void main(void)" \
        "\n" \
        "{" \
            "gl_Position = u_mvpMatrix * a_position;" \
            "a_texcoord_out = a_texcoord;" \
            "\n" \
        "}";

    // Create the Vertex Shader object.
    GLuint vertexShaderObj = glCreateShader(GL_VERTEX_SHADER);

    // Give the shader source to shader object.
    // Actually 3rd parameter is array if you have multiple shader source code
    // However, we have only one source code string
    glShaderSource(vertexShaderObj, 1, (const GLchar **)&vertexShaderSrcCode, NULL);

    // Compile the Shader source code for GPU format
    glCompileShader(vertexShaderObj);

    GLint status;
    GLint infoLogLength;
    char* log = NULL;

    glGetShaderiv(vertexShaderObj, GL_COMPILE_STATUS, &status);

    // If there is an error
    if (status == GL_FALSE)
    {
        glGetShaderiv(vertexShaderObj, GL_INFO_LOG_LENGTH, &infoLogLength);
        if (infoLogLength > 0)
        {
            log = (char*) malloc(infoLogLength);
            if (log != NULL)
            {
                GLsizei written;
                glGetShaderInfoLog(vertexShaderObj, infoLogLength, &written, log);
                fprintf(gpFile, "Vertex Shader Compilation Log: %s\n", log);
                free(log);
                log = NULL;
                uninitialize();
            }
        }
    }

    // Fragement Shader
    const GLchar* fragmentShaderSrcCode = 
        "#version 460 core" \
        "\n" \
        "in vec2 a_texcoord_out;" \
        "uniform sampler2D u_textureSampler;" \
        "out vec4 FragColor;" \
        "\n" \
        "vec4 color;"
        "\n" \
        "void main(void)" \
        "{" \
            "color = texture(u_textureSampler, a_texcoord_out);\n" \
            "FragColor = color ;" \
            "\n" \
        "}";
    
     // Create the Fragment Shader object.
    GLuint fragementShaderObj = glCreateShader(GL_FRAGMENT_SHADER);

    // Give the shader source to shader object.
    // Actually 3rd parameter is array if you have multiple shader source code
    // However, we have only one source code string
    glShaderSource(fragementShaderObj, 1, (const GLchar **)&fragmentShaderSrcCode, NULL);

    // Compile the Shader source code for GPU format
    glCompileShader(fragementShaderObj);

    status = 0;
    infoLogLength = 0;
    log = NULL;

    glGetShaderiv(fragementShaderObj, GL_COMPILE_STATUS, &status);

    // If there is an error
    if (status == GL_FALSE)
    {
        glGetShaderiv(fragementShaderObj, GL_INFO_LOG_LENGTH, &infoLogLength);
        if (infoLogLength > 0)
        {
            log = (char*) malloc(infoLogLength);
            if (log != NULL)
            {
                GLsizei written;
                glGetShaderInfoLog(fragementShaderObj, infoLogLength, &written, log);
                fprintf(gpFile, "Fragment Shader Compilation Log: %s\n", log);
                free(log);
                log = NULL;
                uninitialize();
            }
        }
    }

    // Shader Program Object
    shaderProgramObj = glCreateProgram();
    
    // Attach desired shader object to the program object
    glAttachShader(shaderProgramObj, vertexShaderObj);
    glAttachShader(shaderProgramObj, fragementShaderObj);

    // Pre-linked binding of Shader program object
    glBindAttribLocation(shaderProgramObj, MVD_ATTRIBUTE_POSITION, "a_position");
    glBindAttribLocation(shaderProgramObj, MVD_ATTRIBUTE_TEXTURE0, "a_texcoord");

    // Link the program
    glLinkProgram(shaderProgramObj);

    status = 0;
    infoLogLength = 0;
    log = NULL;

    glGetProgramiv(shaderProgramObj, GL_LINK_STATUS, &status);

    if (status == GL_FALSE)
    {
        glGetProgramiv(shaderProgramObj, GL_INFO_LOG_LENGTH, &infoLogLength);

        if (infoLogLength > 0)
        {
            log = (char*) malloc(infoLogLength);

            if (log != NULL)
            {
                GLsizei written;

                glGetProgramInfoLog(shaderProgramObj, infoLogLength, &written, log);
                fprintf(gpFile, "Shader Program Link Log: %s\n", log);
                free(log);
                uninitialize();
            }
        }
    }

    // Why post linking
    // Because without shaders get attached to shader program object it will not know
    mvpMatrixUniform = glGetUniformLocation(shaderProgramObj, "u_mvpMatrix");
    textureSamplerUniform = glGetUniformLocation(shaderProgramObj, "u_textureSampler");


    const GLfloat cubePosition[] =
    {
        // top
        1.0f, 1.0f, -1.0f,
        -1.0f, 1.0f, -1.0f, 
        -1.0f, 1.0f, 1.0f,
        1.0f, 1.0f, 1.0f,  

        // bottom
        1.0f, -1.0f, -1.0f,
       -1.0f, -1.0f, -1.0f,
       -1.0f, -1.0f,  1.0f,
        1.0f, -1.0f,  1.0f,

        // front
        1.0f, 1.0f, 1.0f,
       -1.0f, 1.0f, 1.0f,
       -1.0f, -1.0f, 1.0f,
        1.0f, -1.0f, 1.0f,

        // back
        1.0f, 1.0f, -1.0f,
       -1.0f, 1.0f, -1.0f,
       -1.0f, -1.0f, -1.0f,
        1.0f, -1.0f, -1.0f,

        // right
        1.0f, 1.0f, -1.0f,
        1.0f, 1.0f, 1.0f,
        1.0f, -1.0f, 1.0f,
        1.0f, -1.0f, -1.0f,

        // left
        -1.0f, 1.0f, 1.0f,
        -1.0f, 1.0f, -1.0f, 
        -1.0f, -1.0f, -1.0f, 
        -1.0f, -1.0f, 1.0f
    };

    const GLfloat cubeTexcoords[] = 
    {
        0.0f, 0.0f,
        1.0f, 0.0f,
        1.0f, 1.0f,
        0.0f, 1.0f,

        0.0f, 0.0f,
        1.0f, 0.0f,
        1.0f, 1.0f,
        0.0f, 1.0f,

        0.0f, 0.0f,
        1.0f, 0.0f,
        1.0f, 1.0f,
        0.0f, 1.0f,

        0.0f, 0.0f,
        1.0f, 0.0f,
        1.0f, 1.0f,
        0.0f, 1.0f,

        0.0f, 0.0f,
        1.0f, 0.0f,
        1.0f, 1.0f,
        0.0f, 1.0f,

        0.0f, 0.0f,
        1.0f, 0.0f,
        1.0f, 1.0f,
        0.0f, 1.0f,

    };

    // vao_cube
    glGenVertexArrays(1, &vao_cube);
    glBindVertexArray(vao_cube);

    //vbo_cube_position related code
    glGenBuffers(1, &vbo_cube_position);
    glBindBuffer(GL_ARRAY_BUFFER, vbo_cube_position);

    glBufferData(GL_ARRAY_BUFFER, sizeof(cubePosition), cubePosition, GL_STATIC_DRAW);
    glVertexAttribPointer(MVD_ATTRIBUTE_POSITION, 3, GL_FLOAT, GL_FALSE, 0, NULL);
    glEnableVertexAttribArray(MVD_ATTRIBUTE_POSITION);

    glBindBuffer(GL_ARRAY_BUFFER, 0);

    // vbo_square_color related color
    glGenBuffers(1, &vbo_cube_texcoord);
    glBindBuffer(GL_ARRAY_BUFFER, vbo_cube_texcoord);
    glBufferData(GL_ARRAY_BUFFER, sizeof(cubeTexcoords), cubeTexcoords, GL_STATIC_DRAW);
    glVertexAttribPointer(MVD_ATTRIBUTE_TEXTURE0, 2, GL_FLOAT, GL_FALSE, 0, NULL);
    glEnableVertexAttribArray(MVD_ATTRIBUTE_TEXTURE0);
    glBindBuffer(GL_ARRAY_BUFFER, 0);

    glBindVertexArray(0);

    // Create CUDA-OpenGL interoperability resource
    // Get my OpenGL Buffer as your Graphics Resource, make it writable and discard it after the use
    //cudaResult = cudaGraphicsGLRegisterBuffer(&graphicResource, vbo_gpu, cudaGraphicsMapFlagsWriteDiscard);
    initCUDABuffers(FBO_WIDTH, FBO_HEIGHT);
    // if (cudaResult != cudaSuccess)
    // {
    //     fprintf(gpFile, "CUDA cudaGraphicsGLRegisterBuffer() failed!\n");
    //     uninitialize();
    //     exit(EXIT_FAILURE);
    // }

    // Required Depth and clear color related changes
    glClearDepth(1.0f);
    glEnable(GL_DEPTH_TEST);
    glDepthFunc(GL_LEQUAL);

    // In Programable pipeline below 2 lines are deprecated
    //glShadeModel(GL_SMOOTH);
    //glHint(GL_PERSPECTIVE_CORRECTION_HINT, GL_NICEST);

    // Here Starts OpenGL code
    // this doesn't actually Clear, but actually tells that which Color (blue in  this case) 
    // to be used when we do actual clear
    glClearColor(1.0f, 1.0f, 1.0f, 1.0f);

    glEnable(GL_TEXTURE_2D);

    perspectiveProjectionMatrix = mat4::identity();

    resize(WIN_WIDTH, WIN_HEIGHT);

    //cpuConvolutionArray = (unsigned int*) malloc(FBO_WIDTH * FBO_HEIGHT * 4 * sizeof(unsigned int));
    // FBO Code
    int iRetval;
    createTextureDst(&tex_cudaResult, FBO_WIDTH, FBO_HEIGHT);

    bfboResult = createFBO(FBO_WIDTH, FBO_HEIGHT);
    if (bfboResult == true)
    {
        iRetval = initialize_sphere(FBO_WIDTH, FBO_HEIGHT);
        if (iRetval)
        {
            fprintf(gpFile, "initialize_sphere Failed!!");
            return (-6);
        }        
    }
    else
    {
        fprintf(gpFile, "Create FBO Failed!!");
        return (-6);
    }
    
    kernel[0] = 1;
    kernel[1] = 2;
    kernel[2] = 1;
    kernel[3] = 2;
    kernel[4] = 4;
    kernel[5] = 2;
    kernel[6] = 1;
    kernel[7] = 2;
    kernel[8] = 1;

    genCPUTexture();
    return(0);
}

void printGLInfo()
{
    // Variable Declarations
    GLint numExtensions = 0;

    // Code
    fprintf(gpFile, "OpenGL Vendor: %s\n", glGetString(GL_VENDOR));
    fprintf(gpFile, "OpenGL Renderer: %s\n", glGetString(GL_RENDERER));
    fprintf(gpFile, "OpenGL Version: %s\n", glGetString(GL_VERSION));
    fprintf(gpFile, "GLSL Version: %s\n", glGetString(GL_SHADING_LANGUAGE_VERSION));
    glGetIntegerv(GL_NUM_EXTENSIONS, &numExtensions);

    fprintf(gpFile, "Number of Supported Extensions: %d\n", numExtensions);
    for (int i = 0; i < numExtensions; i++)
    {
        fprintf(gpFile, "%s\n", glGetStringi(GL_EXTENSIONS, i));
    }
}

bool createFBO(GLint textureWidth, GLint textureHeight)
{
    // Code
    void uninitialize(void);
    //1. Check available render buffer Size
    int maxRenderbufferSize;

    glGetIntegerv(GL_MAX_RENDERBUFFER_SIZE, &maxRenderbufferSize);
    if (maxRenderbufferSize < textureWidth || maxRenderbufferSize < textureHeight)
    {
        fprintf(gpFile, "Insufficient Render buffer size");
        return false;
    }
    
    //2. Create frame buffer object
    glGenFramebuffersEXT(1, &fbo);
    glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, fbo);

    // 3. Create Render Buffer object
    glGenRenderbuffersEXT(1, &rbo);
    glBindRenderbufferEXT(GL_RENDERBUFFER_EXT, rbo);

    // 4. Storage and Format of the Render Buffer
    //This has nothing to with depth. 
    glRenderbufferStorage(GL_RENDERBUFFER_EXT, GL_DEPTH_COMPONENT24, textureWidth, textureHeight);

    //5. Create Empty texture for upcoming target scene
    glGenTextures(1, &fbo_texture);
    glBindTexture(GL_TEXTURE_2D, fbo_texture);

    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);

    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F, textureWidth, textureHeight, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    glFramebufferTexture2DEXT(GL_FRAMEBUFFER_EXT, GL_COLOR_ATTACHMENT0_EXT, GL_TEXTURE_2D, fbo_texture, 0);
  
    // 6. Give RBO to FBO
    glFramebufferRenderbufferEXT(GL_FRAMEBUFFER_EXT,GL_DEPTH_ATTACHMENT_EXT, GL_RENDERBUFFER_EXT, rbo);

    // 7. Check whether FB created successfully or not
    GLenum result = glCheckFramebufferStatus(GL_FRAMEBUFFER_EXT);
    if (result != GL_FRAMEBUFFER_COMPLETE)
    {
        fprintf(gpFile, "Framebuffer is not complete \n");
        return false;
    }
    
    glBindFramebuffer(GL_FRAMEBUFFER_EXT, 0);
    cudaResult = cudaGraphicsGLRegisterImage(&cuda_tex_screen_resource,
                                              fbo_texture, GL_TEXTURE_2D,
                                              cudaGraphicsMapFlagsReadOnly);
    if (cudaResult != cudaSuccess)
    {
        fprintf(gpFile, "CUDA cudaGraphicsGLRegisterImage() failed!\n");
        uninitialize();
        exit(EXIT_FAILURE);
    }
    return true;
}

int initialize_sphere(int width, int height)
{
    // Function declarations
    void resize_sphere(int, int);
    void recordAndBindBuffers(void);
    void getUniformsForShaderProgramForFragment(void);

#pragma region Per Fragment Shaders
     // Vertex Shader
    const GLchar* vertexShader_pfSrcCode = 
       "#version 460 core" \
        "\n" \
        "in vec4 a_position;" \
        "\n" \
        "in vec3 a_normal;" \
        "\n" \
        "uniform mat4 u_modelMatrix;" \
        "\n" \
        "uniform mat4 u_viewMatrix;" \
        "\n" \
        "uniform mat4 u_projectionMatrix;" \
        "\n" \
        "uniform vec4 u_lightPosition[3];" \
        "\n" \
        "uniform int u_lightingEnabled;" \
        "\n" \
        "out vec3 transformedNormals;" \
        "\n" \
        "out vec3 viewerVector;" \
        "\n" \
        "out vec3 lightDirection[3];\n" \
        "\n" \
        "void main(void)" \
        "\n" \
        "{\n" \
            "if(u_lightingEnabled == 1)\n" \
            "{\n" \
                // Goraud
                "vec4 eyeCordinates = u_viewMatrix * u_modelMatrix * a_position;\n" \
                "mat3 normalMatrix = mat3((u_viewMatrix * u_modelMatrix));\n" \
                "transformedNormals = normalMatrix * a_normal;\n" \
                "viewerVector = (-eyeCordinates.xyz);\n" \

                "for(int i = 0; i < 3; i++)" \
                "{\n" \
                    "lightDirection[i] = vec3(u_lightPosition[i]) - eyeCordinates.xyz;\n" \
                "}\n" \
            "}\n" \
            
            "gl_Position = u_projectionMatrix * u_viewMatrix * u_modelMatrix * a_position;" \
            "\n" \
        "}\n";

    // Create the Vertex Shader object.
    GLuint vertexShader_pfObj = glCreateShader(GL_VERTEX_SHADER);

    // Give the shader source to shader object.
    // Actually 3rd parameter is array if you have multiple shader source code
    // However, we have only one source code string
    glShaderSource(vertexShader_pfObj, 1, (const GLchar **)&vertexShader_pfSrcCode, NULL);

    // Compile the Shader source code for GPU format
    glCompileShader(vertexShader_pfObj);

    int status = 0;
    int infoLogLength = 0;
    char* log = NULL;

    glGetShaderiv(vertexShader_pfObj, GL_COMPILE_STATUS, &status);

    // If there is an error
    if (status == GL_FALSE)
    {
        glGetShaderiv(vertexShader_pfObj, GL_INFO_LOG_LENGTH, &infoLogLength);
        if (infoLogLength > 0)
        {
            log = (char*) malloc(infoLogLength);
            if (log != NULL)
            {
                GLsizei written;
                glGetShaderInfoLog(vertexShader_pfObj, infoLogLength, &written, log);
                fprintf(gpFile, "Vertex Shader Compilation Log: %s\n", log);
                free(log);
                log = NULL;
            }
        }
    }

    // Fragement Shader
    const GLchar* fragmentShader_pfSrcCode = 
       "#version 460 core" \
        "\n" \
        "in vec3 transformedNormals;" \
        "\n" \
        "in vec3 viewerVector;" \
        "\n" \
        "in vec3 lightDirection[3];\n" \
        "uniform vec3 u_la[3];" \
        "\n" \
        "uniform vec3 u_ld[3];" \
        "\n" \
        "uniform vec3 u_ls[3];" \
        "\n" \
        "uniform vec3 u_ka;" \
        "\n" \
        "uniform vec3 u_kd;" \
        "\n" \
        "uniform vec3 u_ks;" \
        "\n" \
        "uniform float u_materialShininess;" \
        "\n" \
        "uniform int u_lightingEnabled;" \
        "\n" \
        "vec3 phong_ads_light;" \
        "\n" \
        "out vec4 FragColor;" \
        "\n" \
        "void main(void)\n" \
        "{\n" \
            "vec3 ambient[3];\n" \
            "vec3 diffused[3];\n" \
            "vec3 reflectionVector[3];\n" \
            "vec3 specular[3]; \n" \
            "vec3 normalized_lightDirection[3];\n" \
            "vec3 normalized_transformed_normals = normalize(transformedNormals);\n" \
            "vec3 normalized_viewerVector = normalize(viewerVector);\n" \
            "if(u_lightingEnabled == 1)\n" \
            "{\n" \
                "for(int i = 0; i < 3; i++)" \
                "{\n" \
                    "normalized_lightDirection[i] = normalize(lightDirection[i]);\n" \
                    "ambient[i] = u_la[i] * u_ka;\n" \
                    "diffused[i] = u_ld[i] * u_kd * max(dot(normalized_lightDirection[i], normalized_transformed_normals), 0.0);\n" \
                    "reflectionVector[i] = reflect(-normalized_lightDirection[i], normalized_transformed_normals);\n" \
                    "specular[i] = u_ls[i] * u_ks * pow(max(dot(reflectionVector[i], normalized_viewerVector), 0.0), u_materialShininess);\n" \

                    "phong_ads_light += ambient[i] + diffused[i] + specular[i];\n" \
                "}\n" \
            "}\n" \
            "else\n" \
            "{" \
                "phong_ads_light = vec3(1.0, 1.0, 1.0);\n" \
            "}\n" \

            "FragColor = vec4(phong_ads_light, 1.0);" \
            "\n" \
        "}\n";
    
     // Create the Fragment Shader object.
    GLuint fragementShader_pfObj = glCreateShader(GL_FRAGMENT_SHADER);

    // Give the shader source to shader object.
    // Actually 3rd parameter is array if you have multiple shader source code
    // However, we have only one source code string
    glShaderSource(fragementShader_pfObj, 1, (const GLchar **)&fragmentShader_pfSrcCode, NULL);

    // Compile the Shader source code for GPU format
    glCompileShader(fragementShader_pfObj);

    status = 0;
    infoLogLength = 0;
    log = NULL;

    glGetShaderiv(fragementShader_pfObj, GL_COMPILE_STATUS, &status);

    // If there is an error
    if (status == GL_FALSE)
    {
        glGetShaderiv(fragementShader_pfObj, GL_INFO_LOG_LENGTH, &infoLogLength);
        if (infoLogLength > 0)
        {
            log = (char*) malloc(infoLogLength);
            if (log != NULL)
            {
                GLsizei written;
                glGetShaderInfoLog(fragementShader_pfObj, infoLogLength, &written, log);
                fprintf(gpFile, "Sphere Fragment Shader Compilation Log: %s\n", log);
                free(log);
                log = NULL;
            }
        }
    }

    // Shader Program Object
    shaderProgram_sphere = glCreateProgram();
    
    // Attach desired shader object to the program object
    glAttachShader(shaderProgram_sphere, vertexShader_pfObj);
    glAttachShader(shaderProgram_sphere, fragementShader_pfObj);

    // Pre-linked binding of Shader program object
    glBindAttribLocation(shaderProgram_sphere, MVD_ATTRIBUTE_POSITION, "a_position");
    glBindAttribLocation(shaderProgram_sphere, MVD_ATTRIBUTE_NORMAL, "a_normal");

    // Link the program
    glLinkProgram(shaderProgram_sphere);

    status = 0;
    infoLogLength = 0;
    log = NULL;

    glGetProgramiv(shaderProgram_sphere, GL_LINK_STATUS, &status);

    if (status == GL_FALSE)
    {
        glGetProgramiv(shaderProgram_sphere, GL_INFO_LOG_LENGTH, &infoLogLength);

        if (infoLogLength > 0)
        {
            log = (char*) malloc(infoLogLength);

            if (log != NULL)
            {
                GLsizei written;

                glGetProgramInfoLog(shaderProgram_sphere, infoLogLength, &written, log);
                fprintf(gpFile, "Sphere Shader Program Link Log: %s\n", log);
                free(log);
            }
        }
    }
#pragma endregion

    getUniformsForShaderProgramForFragment();
    // Declaration of vertex data arrays
    
    getSphereVertexData(sphere_vertices, sphere_normals, sphere_textures, sphere_elements);
    numVertices_sphere = getNumberOfSphereVertices();
    numElements_sphere = getNumberOfSphereElements();

    recordAndBindBuffers();

    // Required Depth and clear color related changes
    glClearDepth(1.0f);
    glEnable(GL_DEPTH_TEST);
    glDepthFunc(GL_LEQUAL);

    // Here Starts OpenGL code
    // this doesn't actually Clear, but actually tells that which Color (blue in  this case) 
    // to be used when we do actual clear
    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);

    lights[0].lightAmbient = vmath::vec4(0.0f, 0.0f, 0.0f, 1.0f);
    lights[0].lightDiffused = vmath::vec4(1.0f, 0.0f, 0.0f, 1.0f);
    lights[0].lightSpecular = vmath::vec4(1.0f, 0.0f, 0.0f, 1.0f);
    lights[0].lightPosition = vmath::vec4(0.0f, 0.0f, 0.0f, 1.0f);

    lights[1].lightAmbient = vmath::vec4(0.0f, 0.0f, 0.0f, 1.0f);
    lights[1].lightDiffused = vmath::vec4(0.0f, 1.0f, 0.0f, 1.0f);
    lights[1].lightSpecular = vmath::vec4(0.0f, 1.0f, 0.0f, 1.0f);
    lights[1].lightPosition = vmath::vec4(0.0f, 0.0f, 0.0f, 1.0f);

    lights[2].lightAmbient = vmath::vec4(0.0f, 0.0f, 0.0f, 1.0f);
    lights[2].lightDiffused = vmath::vec4(0.0f, 0.0f, 1.0f, 1.0f);
    lights[2].lightSpecular = vmath::vec4(0.0f, 0.0f, 1.0f, 1.0f);
    lights[2].lightPosition = vmath::vec4(0.0f, 0.0f, 0.0f, 1.0f);

    perspectiveProjectionMatrix_sphere = mat4::identity();

    resize_sphere(FBO_WIDTH, FBO_HEIGHT);

    return(0);
}

void recordAndBindBuffers()
{
    // vao_sphere and vbo_position related code
    glGenVertexArrays(1, &vao_sphere);
    glBindVertexArray(vao_sphere);

    glGenBuffers(1, &vbo_position_sphere);
    glBindBuffer(GL_ARRAY_BUFFER, vbo_position_sphere);

    glBufferData(GL_ARRAY_BUFFER, sizeof(sphere_vertices), sphere_vertices, GL_STATIC_DRAW);
    glVertexAttribPointer(MVD_ATTRIBUTE_POSITION, 3, GL_FLOAT, GL_FALSE, 0, NULL);
    glEnableVertexAttribArray(MVD_ATTRIBUTE_POSITION);

    glBindBuffer(GL_ARRAY_BUFFER, 0);

    glGenBuffers(1, &vbo_normal_sphere);
    glBindBuffer(GL_ARRAY_BUFFER, vbo_normal_sphere);

    glBufferData(GL_ARRAY_BUFFER, sizeof(sphere_normals), sphere_normals, GL_STATIC_DRAW);
    glVertexAttribPointer(MVD_ATTRIBUTE_NORMAL, 3, GL_FLOAT, GL_FALSE, 0, NULL);
    glEnableVertexAttribArray(MVD_ATTRIBUTE_NORMAL);

    glBindBuffer(GL_ARRAY_BUFFER, 0);

    // element vbo
    glGenBuffers(1, &vbo_elements_sphere);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, vbo_elements_sphere);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(sphere_elements), sphere_elements, GL_STATIC_DRAW);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);

    glBindVertexArray(0);
}

void getUniformsForShaderProgramForFragment()
{
    modelMatrixUniform__sphere = glGetUniformLocation(shaderProgram_sphere, "u_modelMatrix");
    viewMatrixUniform__sphere = glGetUniformLocation(shaderProgram_sphere, "u_viewMatrix");
    projectionMatrixUniform__sphere = glGetUniformLocation(shaderProgram_sphere, "u_projectionMatrix");

    laUniform_sphere[0] = glGetUniformLocation(shaderProgram_sphere, "u_la[0]");
    ldUniform_sphere[0] = glGetUniformLocation(shaderProgram_sphere, "u_ld[0]");
    lsUniform_sphere[0] = glGetUniformLocation(shaderProgram_sphere, "u_ls[0]");
    lightPositionUniform_sphere[0] = glGetUniformLocation(shaderProgram_sphere, "u_lightPosition[0]");

    laUniform_sphere[1] = glGetUniformLocation(shaderProgram_sphere, "u_la[1]");
    ldUniform_sphere[1] = glGetUniformLocation(shaderProgram_sphere, "u_ld[1]");
    lsUniform_sphere[1] = glGetUniformLocation(shaderProgram_sphere, "u_ls[1]");
    lightPositionUniform_sphere[1] = glGetUniformLocation(shaderProgram_sphere, "u_lightPosition[1]");

    laUniform_sphere[2] = glGetUniformLocation(shaderProgram_sphere, "u_la[2]");
    ldUniform_sphere[2] = glGetUniformLocation(shaderProgram_sphere, "u_ld[2]");
    lsUniform_sphere[2] = glGetUniformLocation(shaderProgram_sphere, "u_ls[2]");
    lightPositionUniform_sphere[2] = glGetUniformLocation(shaderProgram_sphere, "u_lightPosition[2]");    
    

    kaUniform_sphere = glGetUniformLocation(shaderProgram_sphere, "u_ka");
    kdUniform_sphere = glGetUniformLocation(shaderProgram_sphere, "u_kd");
    ksUniform_sphere = glGetUniformLocation(shaderProgram_sphere, "u_ks");
    materiaShininessUniform_sphere = glGetUniformLocation(shaderProgram_sphere, "u_materialShininess");

    lightingEnabledUniform_sphere = glGetUniformLocation(shaderProgram_sphere, "u_lightingEnabled");
}

void resize(int width, int height)
{
    if(height == 0)
        height = 1;
    winWidth = width;
    winHeight = height;
    // Code
    glViewport(0, 0, (GLsizei) width, (GLsizei)height);
    perspectiveProjectionMatrix = 
    vmath::perspective(45.0f, (GLfloat)width/(GLfloat)height, 0.1f, -100.0f);
}

void resize_sphere(int width, int height)
{
    if(height == 0)
        height = 1;
    // Code
    glViewport(0, 0, (GLsizei) width, (GLsizei)height);
    perspectiveProjectionMatrix_sphere = 
    vmath::perspective(45.0f, (GLfloat)width/(GLfloat)height, 0.1f, -100.0f);
}

void genCPUTexture(void)
{
    glGenTextures(1, &texture_checkerboard);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1); 
    glBindTexture(GL_TEXTURE_2D, texture_checkerboard);

    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glBindTexture(GL_TEXTURE_2D, 0);
}

void cpuConvolution(float* myArray)
{
     // ================ CPU Convolution Start
    for (int x  = 0; x  < FBO_WIDTH; x ++)
    {
        for (int y  = 0; y  < FBO_HEIGHT; y ++)
        {
            //for (int threadId_y = 0; threadId_y < 16 ; threadId_y++)
			{
			//	for (int threadId_x = 0; threadId_x < 16; threadId_x++)
				{
                    // int tx = threadId_x;
                    // int ty = threadId_y;
                    // int bw = blockId_x;
                    // int bh = blockId_y;
                    // int x = blockId_x * bw + tx;
                    // int y = blockId_y * bh + ty;
                    
                    //cpuConvolutionArray[y * FBO_WIDTH+ x] = myArray [y*FBO_WIDTH+x];

                    float rSum = 0.0f, gSum = 0.0f, bSum = 0.0f;
                    float rValue = 0, gValue = 0.0f, bValue = 0.0f;
                    int sample = 0;
                    for (int i = -blur_radius; i <= blur_radius; ++i) {
                        for (int j = -blur_radius; j <= blur_radius; ++j) {
                            int c_y = y + i;
                            int c_x = x + j;

                            if (c_x < 0 || c_x >(FBO_WIDTH - 1) || c_y < 0 || (c_y >(FBO_HEIGHT - 1)))
                            {
                                rValue = 0; gValue = 0; bValue = 0;
                            }
                            else
                            {
                                rValue = myArray[(c_y*FBO_WIDTH + c_x) * 4 + 0];
                                gValue = myArray[(c_y*FBO_WIDTH + c_x) * 4 + 1];
                                bValue = myArray[(c_y*FBO_WIDTH + c_x) * 4 + 2];
                            }
                            rSum += rValue * kernel[(i + blur_radius)* 3 + (j + blur_radius)];
                            gSum += gValue * kernel[(i + blur_radius)* 3 + (j + blur_radius)];
                            bSum += bValue * kernel[(i + blur_radius)* 3 + (j + blur_radius)];
                            sample += 1;
                        }
                    }
                    // cpuConvolutionArray[x][y][0] = (GLubyte) remap(myArray [(y*FBO_WIDTH + x) * 4 + 0], 0, 1, 0, 255);
                    // cpuConvolutionArray[x][y][1] = (GLubyte) remap(myArray [(y*FBO_WIDTH + x) * 4 + 1] , 0, 1, 0, 255);
                    // cpuConvolutionArray[x][y][2] = (GLubyte) remap(myArray [(y*FBO_WIDTH + x) * 4 + 2] , 0, 1, 0, 255);
                    // cpuConvolutionArray[x][y][3] = (GLubyte) 255;

                    // cpuConvolutionArray[(y*FBO_WIDTH + x) * 4 + 0] = (GLubyte)remap(rSum / sample, 0, 1, 0, 255);
                    // cpuConvolutionArray[(y*FBO_WIDTH + x) * 4 + 1] = (GLubyte)remap(gSum / sample, 0, 1, 0, 255);
                    // cpuConvolutionArray[(y*FBO_WIDTH + x) * 4 + 2] = (GLubyte)remap(bSum / sample, 0, 1, 0, 255);
                    // cpuConvolutionArray[(y*FBO_WIDTH + x) * 4 + 3] = (GLubyte)255;

                    cpuConvolutionArray[x][y][0] = (GLubyte)remap(rSum / sample, 0, 1, 0, 255);
                    cpuConvolutionArray[x][y][1] = (GLubyte) (GLubyte)remap(gSum / sample, 0, 1, 0, 255);
                    cpuConvolutionArray[x][y][2] = (GLubyte) (GLubyte)remap(bSum / sample, 0, 1, 0, 255);
                    cpuConvolutionArray[x][y][3] = (GLubyte) 255;
                }
            }
        }
        
    }
}

void cpuConvolutionv2(float* myArray)
{
    for (int blockId_x  = 0; blockId_x < FBO_WIDTH/16; blockId_x ++)
    {
        for (int blockId_y  = 0; blockId_y < FBO_HEIGHT/16; blockId_y++)
        {
            for (int threadId_y = 0; threadId_y < 16 ; threadId_y++)
			{
			    for (int threadId_x = 0; threadId_x < 16; threadId_x++)
				{
                    int tx = threadId_x;
                    int ty = threadId_y;
                    int bw = 16;
                    int bh = 16;
                    int x = blockId_x * bw + tx;
                    int y = blockId_y * bh + ty;
                    

                    cpuConvolutionArray[x][y][0] = (GLubyte) remap(myArray [(y*FBO_WIDTH + x) * 4 + 0], 0, 1, 0, 255);
                    cpuConvolutionArray[x][y][1] = (GLubyte) remap(myArray [(y*FBO_WIDTH + x) * 4 + 1] , 0, 1, 0, 255);
                    cpuConvolutionArray[x][y][2] = (GLubyte) remap(myArray [(y*FBO_WIDTH + x) * 4 + 2] , 0, 1, 0, 255);
                    cpuConvolutionArray[x][y][3] = (GLubyte) 255;


                }
            }
        }
        
    }
}
void display(void)
{
    void display_sphere(GLint, GLint);
    void update_sphere(void);
    void processImage(void);
    if (bfboResult)
    {
        display_sphere(FBO_WIDTH, FBO_HEIGHT);
        update_sphere();
        if (enable_cuda_postProcess)
        {
            processImage();    
        }
        else
        {
            
        }
        
    }
    
    glClearColor(1.0f, 1.0f, 1.0f, 1.0f);
    resize(winWidth, winHeight);
    // Code
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    // Use the Shader Program Object
    glUseProgram(shaderProgramObj);

    // Triangle

    // Transformations
    mat4 translationMatrix = mat4::identity();
    mat4 rotationMatrix = mat4::identity();
    mat4 modelViewMatrix = mat4::identity();
    mat4 modelViewProjectionMatrix = mat4::identity();

    // Cube    
    // Transformations
    mat4 scaleMatrix = mat4::identity();
    mat4 rotationMatrix_x = mat4::identity();
    mat4 rotationMatrix_y = mat4::identity();
    mat4 rotationMatrix_z = mat4::identity();
    rotationMatrix = mat4::identity();
    modelViewMatrix = mat4::identity();
    modelViewProjectionMatrix = mat4::identity();

    // glTranslatef from FFP is replaced with below line
    translationMatrix = vmath::translate(0.0f, 0.0f, -4.0f);
    scaleMatrix = vmath::scale(0.75f, 0.75f, 0.75f);
    rotationMatrix_x = vmath::rotate(angleCube, 1.0f, 0.0f, 0.0f);
    rotationMatrix_y = vmath::rotate(angleCube, 0.0f, 1.0f, 0.0f);
    rotationMatrix_y = vmath::rotate(angleCube, 0.0f, 0.0f, 1.0f);
    rotationMatrix = rotationMatrix_x * rotationMatrix_y * rotationMatrix_z;
    modelViewMatrix = translationMatrix * scaleMatrix * rotationMatrix;
    modelViewProjectionMatrix = perspectiveProjectionMatrix * modelViewMatrix;

    glUniformMatrix4fv(mvpMatrixUniform, 1, GL_FALSE, modelViewProjectionMatrix);
    glActiveTexture(GL_TEXTURE0);
    if (enable_cuda_postProcess)
    {
        glBindTexture(GL_TEXTURE_2D, tex_cudaResult);
    }
    else
    {
        //glBindTexture(GL_TEXTURE_2D, fbo_texture);
        float *new_array = (float *)malloc(FBO_WIDTH * FBO_HEIGHT * 4 * sizeof(float));
            glActiveTexture(GL_TEXTURE0);
            glBindTexture(GL_TEXTURE_2D, fbo_texture);
            /* get texture data from video memory */
            glGetTexImage(GL_TEXTURE_2D, 0, GL_RGBA, GL_FLOAT, (void*)(new_array));
            glBindTexture(GL_TEXTURE_2D, 0);

                      
            glActiveTexture(GL_TEXTURE0);
            glBindTexture(GL_TEXTURE_2D, texture_checkerboard);            
            
            // Below function is deprecated
            //glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_REPLACE);

            //glBindTexture(GL_TEXTURE_2D, 0);

           // CPU Convoultion call should be here
           cpuConvolutionv2(new_array);
           glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, FBO_WIDTH, FBO_HEIGHT, 0, GL_RGBA, GL_UNSIGNED_BYTE, (void *)cpuConvolutionArray);
    }
    //
    glUniform1i(textureSamplerUniform, 0);
    glBindVertexArray(vao_cube);
    
    // Here there should be the drawing of Graphics / Scenes / Animation
    glDrawArrays(GL_TRIANGLE_FAN, 0, 4);
    glDrawArrays(GL_TRIANGLE_FAN, 4, 4);
    glDrawArrays(GL_TRIANGLE_FAN, 8, 4);
    glDrawArrays(GL_TRIANGLE_FAN, 12, 4);
    glDrawArrays(GL_TRIANGLE_FAN, 16, 4);
    glDrawArrays(GL_TRIANGLE_FAN, 20, 4);
    glBindVertexArray(0);
    glBindTexture(GL_TEXTURE_2D, 0);

    // Un-use the Program
    glUseProgram(0);
    cudaDeviceSynchronize();
    SwapBuffers(ghdc);
}

void update(void)
{
    // Code
    
    angleCube += 1.0f;
    if (angleCube >= 360.0f)
    {
        angleCube -= 360.0f;
    }
}

void display_sphere(GLint textureWidth, GLint textureHeight)
{
    // Code
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    resize_sphere(textureWidth, textureHeight);

    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    // Use the Shader Program Object
    glUseProgram(shaderProgram_sphere);
    
    // Transformations
    mat4 translationMatrix = mat4::identity();
    //mat4 modelViewMatrix = mat4::identity();
    mat4 modelMatrix = mat4::identity();
    mat4 viewMatrix = mat4::identity();

    // glTranslatef from FFP is replaced with below line
    translationMatrix = vmath::translate(0.0f, 0.0f, -2.0f);
    modelMatrix = translationMatrix;

    glUniformMatrix4fv(modelMatrixUniform__sphere, 1, GL_FALSE, modelMatrix);
    glUniformMatrix4fv(viewMatrixUniform__sphere, 1, GL_FALSE, viewMatrix);
    glUniformMatrix4fv(projectionMatrixUniform__sphere, 1, GL_FALSE, perspectiveProjectionMatrix_sphere);

    // Sending light related uniforms
    if (bLight == TRUE)
    {
        lights[0].lightPosition[1] = 15 * -sinf(lightAngleZero_sphere);
        lights[0].lightPosition[2] = 15 * cos(-lightAngleZero_sphere);

        lights[1].lightPosition[0] =  15 * cosf(-lightAngleOne_sphere);
        lights[1].lightPosition[2] =  15 * -sinf(lightAngleOne_sphere);

        lights[2].lightPosition[0] =  15 * -sin(-lightAngleTwo_sphere);
        lights[2].lightPosition[1] =  15 * -cos(lightAngleTwo_sphere);
        
        {
            glUniform1i(lightingEnabledUniform_sphere, 1);
            for (int i = 0; i < 3; i++)
            {
                glUniform3fv(laUniform_sphere[i], 1, lights[i].lightAmbient);
                glUniform3fv(ldUniform_sphere[i], 1, lights[i].lightDiffused);
                glUniform3fv(lsUniform_sphere[i], 1, lights[i].lightSpecular);
                glUniform4fv(lightPositionUniform_sphere[i], 1, lights[i].lightPosition);
            }

            glUniform3fv(kaUniform_sphere, 1, materialAmbient_sphere);
            glUniform3fv(kdUniform_sphere, 1, materialDiffused_sphere);
            glUniform3fv(ksUniform_sphere, 1, materialSpecular_sphere);
            glUniform1f(materiaShininessUniform_sphere, materialShininess_sphere);

            glUniformMatrix4fv(modelMatrixUniform__sphere, 1, GL_FALSE, modelMatrix);
            glUniformMatrix4fv(viewMatrixUniform__sphere, 1, GL_FALSE, viewMatrix);
            glUniformMatrix4fv(projectionMatrixUniform__sphere, 1, GL_FALSE, perspectiveProjectionMatrix_sphere);
        }        
    }
    else
    {
        glUniform1i(lightingEnabledUniform_sphere, 0);
        glUniform1i(lightingEnabledUniform_sphere, 0);
    }

    glBindVertexArray(vao_sphere);

    // *** draw, either by glDrawTriangles() or glDrawArrays() or glDrawElements()
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, vbo_elements_sphere);
    glDrawElements(GL_TRIANGLES, numElements_sphere, GL_UNSIGNED_SHORT, 0);

    glBindVertexArray(0);

    // Un-use the Program
    glUseProgram(0);
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
}

void update_sphere(void)
{
    // Code
    lightAngleZero_sphere += 0.05f;
    if (lightAngleZero_sphere >= 360.0f)
    {
        lightAngleZero_sphere -= 360.0f;
    }
    
    lightAngleOne_sphere += 0.05f;
    if (lightAngleOne_sphere >= 360.0f)
    {
        lightAngleOne_sphere -= 360.0f;
    }

    lightAngleTwo_sphere += 0.05f;
    if (lightAngleTwo_sphere >= 360.0f)
    {
        lightAngleTwo_sphere -= 360.0f;
    }
}

void uninitialize(void)
{
    void uninitialize_sphere(void);
    GLsizei numAttachedShaders;
    // Function declarations
    void ToggleFullScreen(void);

    //Code
    // Convention not compulsion
    // Because user can press escape in Full screen mode and OS takes lot of pain to make it full screen
    // Yasya Gruhe Mata Nasti, Tasy gruhe haritaki (Hirada)
    if(gbFullScreen)
    {
        ToggleFullScreen();
    }
    uninitialize_sphere();
    // Deletion and uninitialization of vbo_position
     if (fbo)
    {
        glDeleteFramebuffers(1, &fbo);
        fbo = 0;
    }
     if (rbo)
    {
        glDeleteRenderbuffers(1, &rbo);
        rbo = 0;
    }
    if (fbo_texture)
    {
        glDeleteTextures(1, &fbo_texture);
        fbo_texture = 0;
    }
    if (vbo_cube_texcoord)
    {
        glDeleteBuffers(1, &vbo_cube_texcoord);
        vbo_cube_texcoord = 0;
    }
    if (vbo_cube_position)
    {
        glDeleteBuffers(1, &vbo_cube_position);
        vbo_cube_position = 0;
    }
    // Deletion and uninitialization of vao
    if (vao_cube)
    {
        glDeleteVertexArrays(1, &vao_cube);
        vao_cube = 0;
    }
    // Shader Uninitalization
    if (shaderProgramObj)
    {
        // Use program
        glUseProgram(shaderProgramObj);

        // Get the number of Attached shaders
        glGetProgramiv(shaderProgramObj, GL_ATTACHED_SHADERS, &numAttachedShaders);
        
        GLuint *shaderObjects = NULL;
        shaderObjects = (GLuint*) malloc(sizeof(GLuint) * numAttachedShaders);
        
        // Fill empty buffer with attached shared the objects
        glGetAttachedShaders(shaderProgramObj, numAttachedShaders, &numAttachedShaders, shaderObjects);
        
        // Loop the attached shaders, detach each shader and then delete each shader
        for (GLsizei i = 0; i < numAttachedShaders; i++)
        {
            glDetachShader(shaderProgramObj, shaderObjects[i]);
            glDeleteShader(shaderObjects[i]);
            shaderObjects[i] = 0;
        }
        
        free(shaderObjects);
        shaderObjects = NULL;

        // Un-use the program
        glUseProgram(0);

        // Delete the Program object
        glDeleteProgram(shaderProgramObj);
        shaderProgramObj = 0;
    }
    
    if (wglGetCurrentContext() == ghrc)
    {
        // Get the responsibilities out from ghrc
        wglMakeCurrent(NULL, NULL);
    }

    if (ghrc)
    {
        // Delete the the ghrc
        wglDeleteContext(ghrc);
        ghrc = NULL;
    }

    if (ghdc)
    {
        ReleaseDC(ghwnd, ghdc);
        ghdc = NULL;
    }
    
    if(ghwnd)
    {
        DestroyWindow(ghwnd);
        ghwnd = NULL;
    }
    
    if (gpFile)
    {
        fprintf(gpFile, "Log File Is Closed Successfully.\n");
        fclose(gpFile);
        gpFile = NULL;
    }
}

void uninitialize_sphere(void)
{
    void deleteProgram(GLuint, GLsizei);
    GLsizei numAttachedShaders;
    
    // Deletion and uninitialization of vbo_position
    if (vbo_elements_sphere)
    {
        glDeleteBuffers(1, &vbo_elements_sphere);
        vbo_elements_sphere = 0;
    }
    if (vbo_normal_sphere)
    {
        glDeleteBuffers(1, &vbo_normal_sphere);
        vbo_normal_sphere = 0;
    }
    if (vbo_position_sphere)
    {
        glDeleteBuffers(1, &vbo_position_sphere);
        vbo_position_sphere = 0;
    }
    
    // Deletion and uninitialization of vao_sphere
    if (vao_sphere)
    {
        glDeleteVertexArrays(1, &vao_sphere);
        vao_sphere = 0;
    }
    // Shader Uninitalization    
    if (shaderProgram_sphere)
    {
       deleteProgram(shaderProgram_sphere, numAttachedShaders);
    }    
}

void deleteProgram(GLuint shaderProgramObj, GLsizei numAttachedShaders)
{
    // Use program
        glUseProgram(shaderProgramObj);

        // Get the number of Attached shaders
        glGetProgramiv(shaderProgramObj, GL_ATTACHED_SHADERS, &numAttachedShaders);
        
        GLuint *shaderObjects = NULL;
        shaderObjects = (GLuint*) malloc(sizeof(GLuint) * numAttachedShaders);
        
        // Fill empty buffer with attached shared the objects
        glGetAttachedShaders(shaderProgramObj, numAttachedShaders, &numAttachedShaders, shaderObjects);
        
        // Loop the attached shaders, detach each shader and then delete each shader
        for (GLsizei i = 0; i < numAttachedShaders; i++)
        {
            glDetachShader(shaderProgramObj, shaderObjects[i]);
            glDeleteShader(shaderObjects[i]);
            shaderObjects[i] = 0;
        }
        
        free(shaderObjects);
        shaderObjects = NULL;

        // Un-use the program
        glUseProgram(0);

        // Delete the Program object
        glDeleteProgram(shaderProgramObj);
}
