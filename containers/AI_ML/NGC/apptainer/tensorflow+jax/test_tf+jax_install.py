import tensorflow as tf
import jax.numpy as jnp
from jax.lib import xla_bridge

print(tf.reduce_sum(tf.random.normal([1000, 1000])))
print("\n\nTensorFlow device config:")
print(tf.config.list_physical_devices('CPU'))
print(tf.config.list_physical_devices('GPU'))
print('TensorFlow modules installed successully!')

#---------------------------------------------------

print("\n\nJAX device config:")
print(xla_bridge.get_backend().platform)

x = jnp.ones(shape=( 1000,1000))
y = 2 * jnp.zeros(1000)
z = jnp.dot(x, jnp.cos(y))
y2 = jnp.linalg.solve(x, z)
print('Jax modules installed successully!')
