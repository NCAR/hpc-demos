# NUMA Placement for a Numba Stencil Calculation: Measurements

This file holds the results behind [README.md](README.md), from runs of 12
November 2026 with 32 steps each. `Compute` is the average over the 32
steps, with the slowest step in brackets. Node time is what `launch_cf`
reports for each node, to the nearest second, and node-seconds is its total.

| run                    | `Compute`, s | `Est. BW`, GB/s (range) | node time, s       | node-seconds |
| ---------------------- | ------------ | ----------------------- | ------------------ | ------------ |
| bound, 2 nodes         | 2.07 (2.15)  | 20.5 (19.7 – 22.1)      | 11, then 4 on the same node | 15  |
| unbound, 2 nodes       | 2.58 (3.11)  | 16.9 (13.6 – 25.3)      | 11, 14             | 25           |
| bound, 1 node, waves   | 2.08 (2.20)  | 20.5 (19.3 – 22.2)      | 15                 | 15           |
| unbound, 1 node, waves | 2.54 (3.13)  | 13.6 – 25.6, and one at 91.7 | 17            | 17           |

## Binding made the calculation faster and steady

- **Bound steps computed about 1.25 times faster on average** (2.07 s against
  2.58 s), and the slowest bound step 1.45 times faster than the slowest
  unbound one.
- **Every bound step ran at nearly the same speed**, 19.3 to 22.2 GB/s.
  Unbound steps ranged from 13.6 to 25.3 GB/s. A lucky one now and then beat
  every bound step, but most were slower.

## Starting up is a big part of a short step

`Compute` is only 2 to 3 seconds. How long the rest of a step takes depends
on whether the node has run these steps before:

- **On a fresh node, a step takes 9 to 11 seconds**, mostly before it computes
  anything, apparently while 16 Python processes at once load Python, NumPy
  and Numba from the shared file system.
- **Once the node has those files in memory, a step takes 3 to 4 seconds.**
  The bound 2-node run shows this. PBS gave both of its array jobs the same
  node, one after the other. The first took 11 seconds, the second 4.

That startup doesn't depend on placement, and it varies from node to node,
so it blurs the comparison of whole jobs. A real analysis that computes for
minutes per step would see the full effect of binding on its run time. To see
it here, give the steps more work, for example by adding `--iters 400` to the
`calc_anomaly_numba.py` line in `run_step.sh`.

The lesson for your own runs is to look at which part of a step takes the
time. Placement can only speed up the computing.

## Waves: one node instead of two

Running all 32 steps on one node, 16 at a time, took 15 seconds bound and 17
unbound, against two nodes for 11 to 14 seconds each. Jobs are charged by node
time, so waves used no more node-seconds, and a one-node job may also wait
less in the queue. Waves gain from the startup effect above. The second 16
steps start on a node that already has Python and Numba loaded, and they took
3 to 4 seconds each instead of 9 to 11.

Because a new step starts as soon as any one finishes, the steps don't stay
in step. In the unbound run, step 17 started a second before the others
and had the node almost to itself. It computed in 0.46 seconds, at 91.7 GB/s.
Each step's speed depends on how busy the node is.

With `numactl` and waves, the domain of each new step comes from its line in
the command file, not from the step that just finished. If steps in one
domain finish early, a new step can start in a domain that is still full.
Here all 16 bound steps finished within the same second, so that didn't
happen.
