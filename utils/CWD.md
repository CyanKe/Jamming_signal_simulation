# III. PROPOSED APPROACH

Traditional methods typically use a single label to repre-sent categories, which becomes insufficient when address-ing composite jamming. In such cases, a new label mayneed to be introduced to adequately describe the combinedfeatures. For example, suppose that we have $N$ knownjamming types, labeled from class 1 to class $N$ , and anycombination of $k$ $( k \geq 1 )$ ) jamming types can be freely com-bined. In this case, traditional methods would require at least$2 ^ { N } - 1$ labels to fully describe all possible combinations.In contrast, the flexibility of semantic space allows for anycombination of different jamming types to be represented ina multidimensional space, enabling a direct description ofcomposite jamming as “jamming type i and jamming type$j$ .”

Inspired by this, we decided to map the signal space tosemantic space, leveraging the processing power of VLM.First, we convert the sampled signals into CWD images.Next, we train an image encoder and a text encoder to predictthe correct pairings of a batch of (image, text) trainingexamples. Utilizing the advantages of semantic space, wecan effectively recognize unknown composite jamming,addressing the limitations of traditional methods in labelrepresentation.

A. IQ Signal to Image Transformation

Time-frequency analysis is essential for characterizingthe time-varying features of nonstationary signals and di-rectly affects the distinguishability of jamming signals andclassification performance.

Although many time-frequency transforms are availableto convert signals into time-frequency representations, suchas the STFT and the Wigner–Ville distribution (WVD), wehave specifically chosen the CWD [33], which is designedto provide a key improvement over the limitations of thetraditional methods, with a unique ability to provide high-resolution time-frequency representations with cross-termssuppression.

By applying a smoothing function, the CWD enhancestime-frequency localization, making it well suited for themulticomponent, nonlinear characterization of complexradar jamming signals. When considering time-frequencyresolution, cross-term suppression, and radar jamming sig-nal suitability, the STFT suffers from a tradeoff betweenresolution and energy aggregation due to its fixed windowfunction [34]. This makes it difficult to capture both the fasttransient frequency jumps of jamming signals. The WVD,while providing theoretically optimal time-frequency res-olution, has bilinear properties that cause spurious crossterms in multicomponent signals [35]. These cross termscan severely distort the real-time frequency structure in jam-ming signals, such as DFTJ or VGPO. In contrast, the kernelfunction of the CWD has an adaptive smoothing property inthe time-frequency domain [36], which reduces cross termsin multicomponent jamming signals while preserving thehigh resolution of single-component signals.

This property makes it robust to the multicomponentcoupling phenomena of active blanket jamming (e.g., NCJ)and active deception jamming (e.g., VGPO) involved in thestudy. Meanwhile, for nonsmooth continuous modulationtype jamming signals (e.g., LSJ, CSJ), whose frequencyvaries continuously with time, the exponential kernel ofCWD effectively improves the ridge clarity of such sig-nals [37]; for transient impulses and multicomponent su-perposition type jamming signals (e.g., DFTJ, ISCJ, ISDJ,ISRJ), the spatial overlap of the cross terms and the realcomponents in the time-frequency distribution of such sig-nals will reduce the separability of the machine learningfeatures, CWD constrains the cross term energy diffusionthrough the sum function [38] to provide more discrim-inative time-frequency image inputs for subsequent deeplearning models.

In the time domain, CWD is defined as

$$
\begin{array}{l} \mathrm {C W D} _ {y} (n, \omega) = \sum_ {k = - \infty} ^ {\infty} e ^ {- j \omega k} \sum_ {m = - \infty} ^ {\infty} \frac {\sqrt {\sigma}}{4 \pi k ^ {2}} \\ \times e ^ {- \frac {\sigma (m - n) ^ {2}}{4 ^ {*} k ^ {2}}} y (m + k) y ^ {*} (m - k) \tag {13} \\ \end{array}
$$

where t represents the time variable, $\omega$ is the angular fre-quency, and $^ *$ denotes the complex conjugate. The scalingfactor $\sigma = 1$ plays a crucial role in cross-term suppression

by smoothing the distribution. The kernel $G$ acts as a low-pass filter that processes the 2-D Fourier transform withinthe ambiguity function of Cohen’s class.
