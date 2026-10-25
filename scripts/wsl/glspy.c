// LD_PRELOAD shim (aarch64): reports GL calls made on a thread with no current
// EGL context. Mesa/glvnd silently ignore those; the Mali blob does not, so
// they are the suspects for the parallel-presentation corruption.
#define _GNU_SOURCE
#include <EGL/egl.h>
#include <dlfcn.h>
#include <execinfo.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

typedef uint64_t (*Fn)(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t,
                       double, double, double, double, double, double, double, double);

static void report(const char *name) {
    static __thread int inside;
    if (inside) return;
    inside = 1;
    static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
    static char seen[256][48];
    static int count;
    pthread_mutex_lock(&lock);
    int known = 0;
    for (int i = 0; i < count; ++i) known |= strcmp(seen[i], name) == 0;
    if (!known && count < 256) {
        snprintf(seen[count++], sizeof seen[0], "%s", name);
        fprintf(stderr, "[glspy] %s without context on tid %ld\n", name, (long)gettid());
        void *frames[16];
        int n = backtrace(frames, 16);
        backtrace_symbols_fd(frames, n, 2);
    }
    pthread_mutex_unlock(&lock);
    inside = 0;
}

#define WRAP(name)                                                                          \
    uint64_t name(uint64_t a, uint64_t b, uint64_t c, uint64_t d, uint64_t e, uint64_t f,  \
                  uint64_t g, uint64_t h, double p, double q, double r, double s, double t, \
                  double u, double v, double w) {                                          \
        static Fn real;                                                                     \
        if (!real) real = (Fn)dlsym(RTLD_NEXT, #name);                                      \
        if (eglGetCurrentContext() == EGL_NO_CONTEXT) report(#name);                        \
        return real(a, b, c, d, e, f, g, h, p, q, r, s, t, u, v, w);                        \
    }

WRAP(glActiveTexture) WRAP(glAttachShader) WRAP(glBindBuffer) WRAP(glBindBufferBase)
WRAP(glBindFramebuffer) WRAP(glBindImageTexture) WRAP(glBindRenderbuffer) WRAP(glBindTexture)
WRAP(glBindVertexArray) WRAP(glBlendColor) WRAP(glBlendEquation) WRAP(glBlendEquationSeparate)
WRAP(glBlendFunc) WRAP(glBlendFuncSeparate) WRAP(glBlitFramebuffer) WRAP(glBufferData)
WRAP(glBufferSubData) WRAP(glCheckFramebufferStatus) WRAP(glClear) WRAP(glClearBufferuiv)
WRAP(glClearColor) WRAP(glClearDepthf) WRAP(glClearStencil) WRAP(glColorMask)
WRAP(glCompileShader) WRAP(glCreateProgram) WRAP(glCreateShader) WRAP(glCullFace)
WRAP(glDeleteBuffers) WRAP(glDeleteFramebuffers) WRAP(glDeleteProgram) WRAP(glDeleteShader)
WRAP(glDeleteTextures) WRAP(glDeleteVertexArrays) WRAP(glDepthFunc) WRAP(glDepthMask)
WRAP(glDisable) WRAP(glDisableVertexAttribArray) WRAP(glDrawArrays) WRAP(glDrawBuffers)
WRAP(glDrawElements) WRAP(glDrawElementsBaseVertex) WRAP(glEnable)
WRAP(glEnableVertexAttribArray) WRAP(glFinish) WRAP(glFlush) WRAP(glFramebufferRenderbuffer)
WRAP(glFramebufferTexture2D) WRAP(glFrontFace) WRAP(glGenBuffers) WRAP(glGenFramebuffers)
WRAP(glGenRenderbuffers) WRAP(glGenTextures) WRAP(glGenVertexArrays) WRAP(glGetError)
WRAP(glGetIntegerv) WRAP(glGetProgramiv) WRAP(glGetShaderiv) WRAP(glGetString)
WRAP(glGetUniformLocation) WRAP(glLinkProgram) WRAP(glMemoryBarrier) WRAP(glPixelStorei)
WRAP(glProgramBinary) WRAP(glReadPixels) WRAP(glRenderbufferStorage) WRAP(glScissor)
WRAP(glShaderSource) WRAP(glStencilFunc) WRAP(glStencilMask) WRAP(glStencilOp)
WRAP(glTexImage2D) WRAP(glTexParameteri) WRAP(glTexStorage2D) WRAP(glTexSubImage2D)
WRAP(glUniform1f) WRAP(glUniform1i) WRAP(glUniform2f) WRAP(glUniform4fv) WRAP(glUniformMatrix4fv)
WRAP(glUseProgram) WRAP(glVertexAttribDivisor) WRAP(glVertexAttribPointer)
WRAP(glVertexAttribIPointer) WRAP(glViewport)
