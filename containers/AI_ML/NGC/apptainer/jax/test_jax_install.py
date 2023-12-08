
import jax.numpy as jnp
from jax.lib import xla_bridge

print("\n\nJAX device config:")
print(xla_bridge.get_backend().platform)

x = jnp.ones(shape=( 1000,1000))
y = 2 * jnp.zeros(1000)
z = jnp.dot(x, jnp.cos(y))
y2 = jnp.linalg.solve(x, z)
print('Jax modules installed successully!')
