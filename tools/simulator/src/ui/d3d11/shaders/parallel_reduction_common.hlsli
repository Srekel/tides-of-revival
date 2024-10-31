#ifndef _PARALLEL_REDUCTION_COMMON
#define _PARALLEL_REDUCTION_COMMON

#define PARALLEL_REDUCTION_MIN(shared_mem, index_0, index_1) (min(shared_mem[index_0], shared_mem[index_1]))
#define PARALLEL_REDUCTION_MAX(shared_mem, index_0, index_1) (max(shared_mem[index_0], shared_mem[index_1]))
#define PARALLEL_REDUCTION_SUM(shared_mem, index_0, index_1) (shared_mem[index_0] + shared_mem[index_1])

#define SERIAL_OPERATOR_MIN(a, b) (min(a, b))
#define SERIAL_OPERATOR_MAX(a, b) (max(a, b))
#define SERIAL_OPERATOR_SUM(a, b) (a + b)

#if REDUCTION_OPERATOR==1
    #define PARALLEL_REDUCTION_OPERATOR(shared_mem, index_0, index_1) PARALLEL_REDUCTION_MIN(shared_mem, index_0, index_1)
    #define SERIAL_OPERATOR(a, b) SERIAL_OPERATOR_MIN(a, b)
#elif REDUCTION_OPERATOR==2
    #define PARALLEL_REDUCTION_OPERATOR(shared_mem, index_0, index_1) PARALLEL_REDUCTION_MAX(shared_mem, index_0, index_1)
    #define SERIAL_OPERATOR(a, b) SERIAL_OPERATOR_MAX(a, b)
#elif REDUCTION_OPERATOR==3
    #define PARALLEL_REDUCTION_OPERATOR(shared_mem, index_0, index_1) PARALLEL_REDUCTION_SUM(shared_mem, index_0, index_1)
    #define SERIAL_OPERATOR(a, b) SERIAL_OPERATOR_SUM(a, b)
#else
#error no OPERATOR_ defined
#endif

#endif // _PARALLEL_REDUCTION_COMMON