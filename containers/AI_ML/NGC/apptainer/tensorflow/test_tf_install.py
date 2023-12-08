import tensorflow as tf

print(tf.reduce_sum(tf.random.normal([1000, 1000])))
print("\n\nTensorFlow device config:")
print(tf.config.list_physical_devices('CPU'))
print(tf.config.list_physical_devices('GPU'))
print('TensorFlow modules installed successully!')
