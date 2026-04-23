# Exam Prep — DNN Theory Questions

Answers to the required exam questions, tied to the Flowwatch project where possible.

---

## Hvad er en Deep Neural Network model?

A Deep Neural Network (DNN) is a machine learning model made up of layers of connected nodes (neurons). "Deep" means it has more than one hidden layer between input and output. Each layer learns increasingly abstract representations of the input data.

In Flowwatch, the DNN comparison model has:
- 1 input layer (78 features)
- 2 hidden layers (128 → 64 neurons)
- 1 output layer (15 classes)

---

## Hvad er input?

Input is the raw data fed into the network. Each value becomes a node in the input layer.

In Flowwatch: a vector of 78 numbers describing one network flow — packet sizes, inter-arrival times, flag counts, byte ratios, etc.

```python
input_shape=(78,)  # one number per feature
```

---

## Hvad er output?

Output is what the network predicts. The output layer has one node per class, each producing a probability between 0 and 1 (summing to 1 via softmax).

In Flowwatch: 15 probabilities, one per traffic class (BENIGN, DDoS, PortScan, etc.). The class with the highest probability is the prediction.

---

## Hvad er vægte?

Weights are numbers on each connection between neurons. They control how much one neuron influences the next. The network learns by adjusting these weights during training.

Before training: weights are initialised randomly.  
After training: weights encode what the model has learned.

A single neuron with two inputs:
```
output = w1 * x1 + w2 * x2 + bias
```

---

## Hvad er bias?

Bias is an extra number added to the weighted sum before the activation function. It lets the neuron fire even when all inputs are zero, shifting the activation threshold.

Without bias, every neuron would be forced through the origin — the model would have less flexibility to fit the data.

```
output = (w1*x1 + w2*x2) + bias
```

---

## Hvad er hidden layer?

A hidden layer is any layer between the input and output layer. It is "hidden" because its values are not directly observed — they are internal representations the network builds up on its own.

More hidden layers = more abstract representations = deeper network.

In Flowwatch's DNN:
- Hidden layer 1: 128 neurons — learns low-level combinations of features
- Hidden layer 2: 64 neurons — learns higher-level patterns

---

## Hvad er forward propagation?

Forward propagation is the process of passing input through the network layer by layer to produce a prediction.

For each layer:
1. Multiply each input by its weight
2. Sum the results and add bias (sigma function)
3. Apply the activation function
4. Pass the result to the next layer

```
Input (78) → Dense 128 → Dense 64 → Output (15 probabilities)
```

This happens once per prediction at inference time, and once per training sample during training.

---

## Hvad er Summerings-funktion (Sigma)?

The summation function (Σ) is the weighted sum of all inputs to a neuron, plus bias:

```
z = Σ(wᵢ * xᵢ) + b
```

This is just a dot product. The result `z` is then passed to the activation function. By itself it is linear — the activation function is what introduces non-linearity.

---

## Hvad er Aktiverings-funktion?

The activation function is applied to the summation result `z` to introduce non-linearity. Without it, stacking layers would just be matrix multiplication — equivalent to a single linear model that cannot learn complex patterns.

```
output = activation(z)
```

---

## Findes der forskellige? (Are there different ones?)

Yes. Common activation functions:

| Function | Formula | Used where |
|----------|---------|-----------|
| ReLU | `max(0, z)` | Hidden layers — fast, avoids vanishing gradient |
| Sigmoid | `1 / (1 + e⁻ᶻ)` | Binary output (0–1) |
| Softmax | `eᶻⁱ / Σeᶻ` | Multi-class output — normalises to probabilities |
| Tanh | `(eᶻ - e⁻ᶻ) / (eᶻ + e⁻ᶻ)` | Hidden layers — centred around zero |

In Flowwatch's DNN:
- Hidden layers use **ReLU** — standard choice for classification
- Output layer uses **Softmax** — converts raw scores to 15 class probabilities

---

## Hvad er target?

Target (also called label or ground truth) is the correct answer for a training sample. During training the network compares its prediction against the target to calculate how wrong it was.

In Flowwatch: the `Label` column in the CICIDS2017 dataset — e.g. `DDoS`, `BENIGN`, `PortScan`. Encoded as integers 0–14.

---

## Hvad er error?

Error (loss) is the difference between the network's prediction and the target. The loss function quantifies how wrong the prediction is — a single number the network tries to minimise.

In Flowwatch's DNN, the loss function is **sparse categorical cross-entropy**:

```
loss = -log(predicted probability of the correct class)
```

If the model predicts DDoS with probability 0.99 and the true label is DDoS, loss is low.  
If it predicts 0.01, loss is high.

---

## Hvad er back propagation?

Backpropagation is how the network learns from its errors. After forward propagation produces a prediction and the loss is calculated, backpropagation works backwards through the network using the chain rule of calculus to compute how much each weight contributed to the error.

Steps:
1. Calculate loss
2. Compute gradient of loss with respect to output weights
3. Propagate gradients backwards layer by layer
4. Use gradients to update every weight

This is what `model.fit()` does internally on every batch.

---

## Hvad er gradient?

A gradient is the partial derivative of the loss with respect to a single weight. It tells you two things:
- **Direction**: which way to move the weight to reduce loss
- **Magnitude**: how steep the loss surface is — how big a step to take

If the gradient is positive, decreasing the weight reduces the loss.  
If negative, increasing the weight reduces the loss.

---

## Hvad er learning rate?

Learning rate controls how large a step the network takes when updating weights from the gradient. It is the most important hyperparameter to tune.

```
new_weight = old_weight - learning_rate * gradient
```

| Learning rate | Effect |
|---------------|--------|
| Too high | Overshoots the minimum — loss oscillates or diverges |
| Too low | Learns very slowly — may get stuck |
| Just right | Converges steadily to a good solution |

In Flowwatch's DNN: `Adam(learning_rate=0.001)` — Adam adapts the effective learning rate per weight automatically.

---

## Hvad er momentum?

Momentum is a technique that smooths out weight updates by accumulating a velocity in the direction of past gradients. Instead of following the raw gradient each step, the update carries "inertia" from previous steps.

```
velocity = momentum * velocity - learning_rate * gradient
new_weight = old_weight + velocity
```

This helps the network:
- Move faster through flat regions of the loss surface
- Avoid getting stuck in small local minima
- Dampen oscillations in narrow valleys

The Adam optimiser used in Flowwatch incorporates momentum as part of its algorithm (first moment estimate).

---

## Hvordan udregnes en ny vægt?

Using vanilla gradient descent with momentum, the update rule is:

```
velocity  = β * velocity - α * ∂L/∂w
new_weight = old_weight + velocity
```

Where:
- `α` = learning rate
- `β` = momentum coefficient (typically 0.9)
- `∂L/∂w` = gradient of loss with respect to this weight

With the **Adam** optimiser (used in Flowwatch):

```
m = β₁ * m + (1 - β₁) * gradient          # momentum estimate
v = β₂ * v + (1 - β₂) * gradient²         # variance estimate
m̂ = m / (1 - β₁ᵗ)                         # bias correction
v̂ = v / (1 - β₂ᵗ)
new_weight = old_weight - α * m̂ / (√v̂ + ε)
```

In plain terms: Adam scales the learning rate individually for each weight based on how much it has been updated historically — weights that receive large consistent gradients get a smaller effective step, and vice versa.
