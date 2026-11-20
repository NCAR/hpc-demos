// hello_omp.cpp -- minimal OpenMP "hello world" for a launch_cf command file.
//
// Takes one integer on the command line (the step number) and has every
// OpenMP thread report itself.
//
// Build:  CC -fopenmp -o hello_omp.exe hello_omp.cpp     (Derecho, Cray wrapper)
//         g++ -fopenmp -o hello_omp.exe hello_omp.cpp    (GNU)

#include <omp.h>
#include <sched.h>
#include <unistd.h>

#include <cstdlib>
#include <iostream>
#include <stdexcept>
#include <string>

int main(int argc, char *argv[]) {
    if (argc != 2) {
        std::cerr << "usage: " << argv[0] << " <step_number>\n";
        return 1;
    }

    int step = 0;
    try {
        step = std::stoi(argv[1]);
    } catch (const std::exception &) {
        std::cerr << "error: '" << argv[1] << "' is not an integer\n";
        return 1;
    }

    // The PBS array index, if we are running inside a job array. Not required,
    // but handy for confirming which array element picked up this step.
    const char *array_index = std::getenv("PBS_ARRAY_INDEX");

    char host[256];
    std::string hostname = "unknown";
    if (gethostname(host, sizeof(host)) == 0) {
        hostname = host;
    }

#pragma omp parallel
    {
        const int tid = omp_get_thread_num();
        const int nthreads = omp_get_num_threads();
        const int cpu = sched_getcpu();

        // Serialize the writes so lines from different threads don't interleave.
#pragma omp critical
        {
            std::cout << "step " << step << " | host " << hostname << " | core " << cpu 
                      << " | thread " << tid << " of " << nthreads;
            if (array_index) std::cout << " | PBS_ARRAY_INDEX=" << array_index;
            std::cout << std::endl;
        }
    }

    return 0;
}
